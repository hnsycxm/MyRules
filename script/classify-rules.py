#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
规则分类器：把混合清单拆成「IP 规则」与「域名规则」两个文件，均为 Mihomo 可直接编译的文本。

用法：
    classify-rules.py <输入文件> <IP 输出文件> <域名输出文件> [--config <config.yaml>]

stdout 输出三行供 shell 解析：
    第一行 = IP 条目数（合并重叠/相邻网段之后）
    第二行 = 域名规则条数（规范化、去重之后，尚未做冗余归并）
    第三行 = 无法识别的行数
所有告警与示例都写到 stderr，不会污染上面三行。

Mihomo 规范对齐：
  * 域名输出是 behavior: domain 规则集的文本写法（见 sort-clash.py 文档头）：
    +.x / .x / *.x / a.*.x / 精确 x，语义原样保留，不会被放宽；
    DOMAIN-SUFFIX,x → +.x；DOMAIN,x → 精确 x；
    裸域名按 rules.bare_domain 解释（suffix 为历史默认，exact 为 Mihomo 原生语义）；
  * IP 输出是 behavior: ipcidr 规则集的文本写法：每行一个 CIDR（IPv4 补 /32，IPv6 补 /128），
    IPv4 与 IPv6 可以同处一个规则集；
  * mrs 只支持 domain / ipcidr，因此 DOMAIN-KEYWORD / DOMAIN-REGEX / DOMAIN-WILDCARD /
    GEOIP / PROCESS-NAME 等规则类型无法无损表达：不再静默丢弃，计入「无法识别」并报告。

行解析与域名判断复用同目录的 sort-clash.py，分类器认定的域名一定能通过清洗器。

终端编码：stdout / stderr 统一按 UTF-8 输出（见 sort-clash.py::ensure_utf8_stdio），
避免在 GBK 等非 UTF-8 控制台打印中文告警/emoji 时抛 UnicodeEncodeError 而误报失败。
"""

import argparse
import importlib.util
import ipaddress
import sys
from pathlib import Path
from typing import Dict, List, Set

IP_RULE_TYPES = ('IP-CIDR', 'IP-CIDR6')


def load_sort_clash():
    """按文件路径加载同目录下的 sort-clash.py（文件名含连字符，无法直接 import）。"""
    path = Path(__file__).resolve().with_name('sort-clash.py')
    spec = importlib.util.spec_from_file_location('sort_clash', str(path))
    if spec is None or spec.loader is None:
        raise ImportError(f'无法加载 {path}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_ip(value: str):
    """解析 IP 或网段（IPv4 补 /32，IPv6 补 /128）；不是合法地址返回 None。"""
    try:
        return ipaddress.ip_network(value, strict=False)
    except ValueError:
        return None


def collapse_networks(networks: list) -> List[str]:
    """去重并合并重叠/相邻网段；IPv4 在前、IPv6 在后，各自按地址排序。"""
    result: List[str] = []
    for version in (4, 6):
        group = [n for n in networks if n.version == version]
        result.extend(str(n) for n in ipaddress.collapse_addresses(group))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description='把混合规则清单拆分为 Mihomo 的 ipcidr / domain 文本')
    parser.add_argument('src', help='输入文件')
    parser.add_argument('ip_out', help='IP 规则输出文件（ipcidr 文本）')
    parser.add_argument('domain_out', help='域名规则输出文件（domain 文本）')
    parser.add_argument('--config', type=Path, default=None, help='配置文件路径（默认：项目根目录/config.yaml）')
    args = parser.parse_args()

    try:
        sort_clash = load_sort_clash()
    except Exception as exc:  # noqa: BLE001
        print(f'加载 sort-clash.py 失败：{exc}', file=sys.stderr)
        return 1

    # 与 sort-clash.py 保持一致：UTF-8 输出，避免 GBK 控制台下 emoji 告警崩溃/乱码
    sort_clash.ensure_utf8_stdio()

    rules_config = sort_clash.load_config(args.config).get('rules', {})
    bare_mode = sort_clash.resolve_bare_mode(rules_config)

    networks: list = []
    patterns: Set[str] = set()
    unrecognized: List[str] = []
    unsupported: Dict[str, int] = {}

    try:
        # utf-8-sig 去 BOM；errors='replace' 让坏字节变成无效字符被拒绝，
        # 而不是被 'ignore' 悄悄拼成另一个合法域名
        with open(args.src, 'r', encoding='utf-8-sig', errors='replace') as handle:
            for raw in handle:
                parsed = sort_clash.split_rule(raw)
                if parsed is None:
                    continue
                rule_type, value = parsed

                if rule_type == '' or rule_type in IP_RULE_TYPES:
                    network = parse_ip(value)
                    if network is not None:
                        networks.append(network)
                        continue

                if rule_type == '' or rule_type in sort_clash.DOMAIN_RULE_TYPES:
                    pattern = sort_clash.normalize_pattern(value, rule_type, bare_mode, validate=True)
                    if pattern is not None:
                        patterns.add(pattern)
                        continue
                elif rule_type not in IP_RULE_TYPES:
                    unsupported[rule_type] = unsupported.get(rule_type, 0) + 1

                unrecognized.append(raw.strip())
    except OSError as exc:
        print(f'无法读取输入文件 {args.src}：{exc}', file=sys.stderr)
        return 1

    ip_lines = collapse_networks(networks)
    domain_lines = sorted(patterns, key=sort_clash.sort_key)

    try:
        for path, items in ((args.ip_out, ip_lines), (args.domain_out, domain_lines)):
            with open(path, 'w', encoding='utf-8', newline='\n') as handle:
                if items:
                    handle.write('\n'.join(items) + '\n')
    except OSError as exc:
        print(f'无法写入输出文件：{exc}', file=sys.stderr)
        return 1

    if unrecognized:
        preview = ' | '.join(unrecognized[:5]) + (' …' if len(unrecognized) > 5 else '')
        print(f'⚠️ {len(unrecognized)} 行无法识别：{preview}', file=sys.stderr)
        if unsupported:
            detail = '、'.join(f'{k}×{v}' for k, v in sorted(unsupported.items()))
            print(f'   其中 mrs（domain/ipcidr）无法表达的规则类型：{detail}', file=sys.stderr)

    # shell 通过 read 逐行解析这三行
    print(len(ip_lines))
    print(len(domain_lines))
    print(len(unrecognized))
    return 0


if __name__ == '__main__':
    sys.exit(main())
