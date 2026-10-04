#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
规则分类器：把混合清单拆成「IP 规则」与「域名规则」两个文件。

由 script/build-combined-rules.sh 调用，输出三行供 shell 解析：
    第一行 = IP 条目数
    第二行 = 域名条目数
    第三行 = 无法识别的行数

设计要点（对应分析报告中的高危问题）：
  * 逐行分类，而不是给整个文件打一个标签，因此「IP 与域名混排」
    或「同一行既有 IP 又有域名」都不会再丢数据；
  * 使用标准库 ipaddress 支持 IPv6 与 CIDR，不再只依赖 IPv4 正则；
  * 保留原始书写形式（域名大小写、IP 掩码），只做必要的去重与排序，
    因此对历史上的文件不会产生额外改动。
"""

import ipaddress
import re
import sys
from typing import List, Tuple

# 与 sort-clash.py 的 extract_domain 保持一致的跳过前缀
SKIP_PREFIXES: Tuple[str, ...] = (
    'payload:',
    '#',
    '!',
    'DOMAIN,',
    'DOMAIN-KEYWORD,',
    'DOMAIN-SUFFIX,',
    'IP-CIDR,',
    'IP-CIDR6,',
)

MD5_LIKE = re.compile(r'^[0-9a-fA-F]{32}$')
# 从整行里挑出「看起来像域名」的片段，用于识别
# "1.2.3.4 pornhub.com" 这类既不是 IP 也不是规范域名的行
DOMAIN_LIKE = re.compile(r'[A-Za-z0-9][A-Za-z0-9-]*\.[A-Za-z]{2,}')


def parse_ip(line: str) -> str:
    """
    尝试把一行解析为 IP 或网段。

    返回带掩码的规范文本（IPv4 补 /32，IPv6 补 /128），
    不是合法地址时返回 None。
    """
    try:
        # 先按网段解析：1.2.3.0/24、2001:db8::/32
        return str(ipaddress.ip_network(line, strict=False))
    except ValueError:
        pass

    try:
        # 再按单地址解析：1.2.3.4、2001:db8::1
        return str(ipaddress.ip_address(line))
    except ValueError:
        return None


def looks_like_domain(line: str) -> bool:
    """判断一行是否「像」域名规则，用于区分拼写错误与真正无法识别的行。"""
    # 域名里不可能有空白：含空白的行（如 "1.2.3.4 pornhub.com"）属于
    # 无法识别的歧义行，交给调用方告警，而不是当作域名混进规则集
    if any(ch.isspace() for ch in line):
        return False
    if line.startswith('+.') or line.startswith('*.'):
        return True
    if MD5_LIKE.match(line):
        return True
    # 整行是一个裸域名，或行内含有域名片段
    return bool(DOMAIN_LIKE.search(line))


def ip_sort_key(text: str):
    """混合 IPv4/IPv6 也能排序：先按版本号，再按网络地址。"""
    network = ipaddress.ip_network(text, strict=False)
    return (network.version, network.network_address, network.prefixlen)


def main() -> int:
    if len(sys.argv) != 4:
        print(
            '用法：classify-rules.py <输入文件> <IP 输出文件> <域名输出文件>',
            file=sys.stderr,
        )
        return 2

    src_path, ip_path, domain_path = sys.argv[1], sys.argv[2], sys.argv[3]

    ips: List[str] = []
    domains: List[str] = []
    unrecognized: List[str] = []

    try:
        with open(src_path, 'r', encoding='utf-8', errors='ignore') as handle:
            for raw in handle:
                line = raw.strip()
                if not line or line.startswith(SKIP_PREFIXES):
                    continue

                parsed = parse_ip(line)
                if parsed is not None:
                    ips.append(parsed)
                    continue

                if looks_like_domain(line):
                    domains.append(line)
                else:
                    unrecognized.append(line)
    except OSError as exc:
        print(f'无法读取输入文件 {src_path}：{exc}', file=sys.stderr)
        return 1

    # 去重并排序；IP 先按版本再按网络地址，域名用不区分大小写的字典序
    unique_ips = sorted(set(ips), key=ip_sort_key)
    unique_domains = sorted(set(domains), key=str.lower)

    def write(path: str, items: List[str]) -> None:
        with open(path, 'w', encoding='utf-8') as handle:
            if items:
                handle.write('\n'.join(items) + '\n')

    try:
        write(ip_path, unique_ips)
        write(domain_path, unique_domains)
    except OSError as exc:
        print(f'无法写入输出文件：{exc}', file=sys.stderr)
        return 1

    # shell 通过 read 逐行解析这三行
    print(len(unique_ips))
    print(len(unique_domains))
    print(len(unrecognized))
    return 0


if __name__ == '__main__':
    sys.exit(main())
