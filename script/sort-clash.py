#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
域名排序和去重脚本
用于处理域名列表，执行去重、排序和子域名优化
"""

import sys
import re
import os
from pathlib import Path
from typing import Optional, Set, List, Dict, Any

# PyYAML 是唯一的外部依赖：缺失时回退到默认配置，而不是让构建整体失败
try:
    import yaml
except ImportError:  # pragma: no cover - 取决于运行环境
    yaml = None  # type: ignore[assignment]

# 多段公共后缀（不完整的 PSL 子集）。
# 作用：当清单里误写了 "co.jp" 这类过宽的父域时，不再让它把
# "dmm.co.jp"、"amazon.co.jp" 等真实域名整片吸收掉。
MULTI_PART_PUBLIC_SUFFIXES: frozenset = frozenset({
    # 日本
    'co.jp', 'ne.jp', 'or.jp', 'ac.jp', 'ad.jp', 'ed.jp', 'go.jp', 'gr.jp', 'lg.jp',
    # 中国大陆
    'com.cn', 'net.cn', 'org.cn', 'gov.cn', 'edu.cn', 'ac.cn',
    # 港台
    'com.hk', 'org.hk', 'net.hk', 'edu.hk', 'gov.hk',
    'com.tw', 'org.tw', 'net.tw', 'edu.tw', 'gov.tw',
    # 英国
    'co.uk', 'org.uk', 'me.uk', 'ac.uk', 'gov.uk', 'net.uk', 'sch.uk',
    # 其他常见
    'com.au', 'net.au', 'org.au', 'edu.au', 'gov.au',
    'com.br', 'com.mx', 'com.ar', 'com.tr', 'com.sg', 'com.my', 'com.ph',
    'co.kr', 'or.kr', 'ne.kr', 'go.kr', 're.kr',
    'co.nz', 'co.za', 'co.in', 'co.id', 'co.th', 'co.il',
    # 托管平台（常见于规则清单）
    'github.io', 'gitee.io', 'gitlab.io', 'pages.dev', 'workers.dev',
    'vercel.app', 'netlify.app', 'herokuapp.com', 'blogspot.com',
    'cloudfront.net', 'azurewebsites.net', 'appspot.com',
})

# 规则语法前缀，这类行不是裸域名
RULE_PREFIXES: tuple = (
    'payload:',
    '#',
    '!',
    'DOMAIN,',
    'DOMAIN-KEYWORD,',
    'DOMAIN-SUFFIX,',
    'IP-CIDR,',
    'IP-CIDR6,',
)


def load_config(config_path: Optional[Path] = None) -> Dict[str, Any]:
    """
    加载配置文件

    Args:
        config_path: 配置文件路径，默认为项目根目录/config.yaml

    Returns:
        配置字典
    """
    default_config: Dict[str, Any] = {
        'rules': {
            'remove_subdomains': True,
            'validate_domains': True,
            'sort_domains': True,
        }
    }

    if config_path is None:
        script_dir = Path(__file__).parent
        config_path = script_dir.parent / 'config.yaml'

    if not config_path.exists():
        print(f"警告：配置文件不存在 {config_path}，使用默认配置")
        return default_config

    if yaml is None:
        print("警告：未安装 PyYAML（pip install -r requirements.txt），使用默认配置")
        return default_config

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
            if not isinstance(config, dict):
                print("警告：配置文件格式错误，使用默认配置")
                return default_config
            # 合并默认配置
            if 'rules' not in config or not isinstance(config.get('rules'), dict):
                config['rules'] = dict(default_config['rules'])
            else:
                for key, value in default_config['rules'].items():
                    if key not in config['rules']:
                        config['rules'][key] = value
            return config
    except Exception as e:
        print(f"警告：加载配置文件失败 {e}，使用默认配置")
        return default_config


def is_valid_domain(domain: str) -> bool:
    """
    验证域名格式是否有效

    Args:
        domain: 域名字符串

    Returns:
        是否有效
    """
    if not domain or len(domain) > 253:
        return False

    labels = domain.split('.')

    # 至少有两个标签（二级域名）
    if len(labels) < 2:
        return False

    # 检查每个标签
    for label in labels:
        # 标签不能为空，最大长度 63
        if not label or len(label) > 63:
            return False
        # 标签格式：字母/数字/连字符，不能以连字符开头或结尾
        if not re.match(r'^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$', label):
            return False

    # TLD 不能全是数字，长度至少 2
    tld = labels[-1]
    if tld.isdigit() or len(tld) < 2:
        return False

    return True


def is_public_suffix(domain: str) -> bool:
    """
    判断域名是否为已知的多段公共后缀（例如 co.jp）。

    这类域名本身可以保留在清单里，但不应当作为父域去吸收其他域名。
    """
    lowered = domain.lower()
    if lowered in MULTI_PART_PUBLIC_SUFFIXES:
        return True
    # 单标签域名（如 "com"）同样不能作为父域
    if '.' not in lowered:
        return True
    return False


def can_absorb_subdomains(domain: str) -> bool:
    """
    判断某个域名是否有资格作为「父域」吸收其子域。

    普通父域（example.com）可以；公共后缀（co.jp）不可以，
    这样 "co.jp" 就不会把 "dmm.co.jp"、"amazon.co.jp" 一并吞掉。
    """
    return not is_public_suffix(domain)


def extract_domain(line: str, validate: bool = True) -> Optional[str]:
    """
    从规则中提取有效域名

    Args:
        line: 输入行
        validate: 是否验证域名格式

    Returns:
        提取的域名，无效则返回 None
    """
    line = line.strip()
    if not line or 'regexp' in line:
        return None

    # 跳过非域名行
    if line.startswith(RULE_PREFIXES):
        return None

    # 按前缀从长到短匹配：旧版把 '  - \\' 放在 '- \\' 之后，导致它永远不生效
    if line.startswith('  - \\'):
        domain = line[5:]
    elif line.startswith('- \\'):
        domain = line[3:]
    elif line.startswith('+.'):
        domain = line[2:]
    elif '.' in line and not line.startswith('+'):
        domain = line
    else:
        return None

    # 去掉 YAML 行尾的续行反斜杠与空白
    domain = domain.strip()
    if domain.endswith('\\'):
        domain = domain[:-1].strip()

    # 忽略末尾多余的点（"example.com." 与 "example.com" 等价）
    domain = domain.rstrip('.').strip()
    if not domain:
        return None

    if validate and not is_valid_domain(domain):
        return None

    return domain


def remove_subdomains(domains: Set[str]) -> Set[str]:
    """
    移除子域名，只保留父域名

    公共后缀（如 co.jp）不会被当作父域，避免误删真实域名。

    Args:
        domains: 域名集合

    Returns:
        过滤后的域名集合
    """
    # 按反转字符串排序：父域总是紧挨在它的子域之前
    sorted_domains = sorted(domains, key=lambda d: d[::-1])
    kept: List[str] = []
    kept_set: Set[str] = set()
    verbose = bool(os.environ.get('MYRULES_VERBOSE'))

    for domain in sorted_domains:
        # 自右向左找已保留的父域：父域最多比子域少一级标签，
        # 因此反转字典序下只需回看最近保留的那一个
        parent = None
        if kept:
            candidate = kept[-1]
            if domain.endswith('.' + candidate):
                parent = candidate

        if parent is not None and can_absorb_subdomains(parent):
            if verbose:
                print(f"  [子域归并] {domain} 已被 {parent} 覆盖")
            continue

        kept.append(domain)
        kept_set.add(domain)

    return kept_set


def process_domains(file_name: str, rules_config: Dict[str, Any]) -> int:
    """
    处理域名文件

    Args:
        file_name: 输入文件路径
        rules_config: 规则配置

    Returns:
        处理后的域名数量
    """
    validate = rules_config.get('validate_domains', True)

    # 读取并提取域名
    domains: Set[str] = set()
    dropped: List[str] = []
    with open(file_name, 'r', encoding='utf-8') as f:
        for line in f:
            stripped = line.strip()
            domain = extract_domain(stripped, validate=validate)
            if domain:
                domains.add(domain)
            elif validate and stripped and not stripped.startswith(RULE_PREFIXES):
                dropped.append(stripped)

    # 根据配置决定是否移除子域名
    if rules_config.get('remove_subdomains', True):
        domains = remove_subdomains(domains)

    # 根据配置决定是否排序
    if rules_config.get('sort_domains', True):
        sorted_domains = sorted(domains)
    else:
        sorted_domains = list(domains)

    # 写入文件
    with open(file_name, 'w', encoding='utf-8') as f:
        f.writelines(f"{domain}\n" for domain in sorted_domains)

    if dropped:
        preview = ', '.join(dropped[:5]) + (" …" if len(dropped) > 5 else "")
        print(f"⚠️ 跳过 {len(dropped)} 行无法解析为域名的内容：{preview}")

    return len(sorted_domains)


def main() -> None:
    """主函数"""
    if len(sys.argv) < 2:
        print("请提供输入文件路径作为参数")
        print("用法：python sort-clash.py <文件名> [--config <配置文件路径>]")
        sys.exit(1)

    file_name = sys.argv[1]
    config_path = None

    # 解析命令行参数
    if '--config' in sys.argv:
        config_index = sys.argv.index('--config')
        if config_index + 1 < len(sys.argv):
            config_path = Path(sys.argv[config_index + 1])

    # 加载配置
    config = load_config(config_path)
    rules_config = config.get('rules', {})

    # 检查文件
    if not os.path.isfile(file_name):
        print(f"错误：'{file_name}' 不是一个有效的文件")
        sys.exit(1)

    try:
        count = process_domains(file_name, rules_config)
        print(f"✅ 处理完成，生成的规则总数为：{count}")
    except IOError as e:
        print(f"❌ 文件操作错误：{e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ 处理过程中发生错误：{e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
