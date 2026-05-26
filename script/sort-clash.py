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
import yaml


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
            'sort_domains': True
        }
    }

    if config_path is None:
        script_dir = Path(__file__).parent
        config_path = script_dir.parent / 'config.yaml'

    if not config_path.exists():
        print(f"警告：配置文件不存在 {config_path}，使用默认配置")
        return default_config

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
            if not isinstance(config, dict):
                print("警告：配置文件格式错误，使用默认配置")
                return default_config
            # 合并默认配置
            if 'rules' not in config:
                config['rules'] = default_config['rules']
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
    skip_prefixes = ('payload:', '#', '!', 'DOMAIN,', 'DOMAIN-KEYWORD,',
                     'DOMAIN-SUFFIX,', 'IP-CIDR,', 'IP-CIDR6,')
    if line.startswith(skip_prefixes):
        return None

    # 提取域名
    if line.startswith('+.'):
        domain = line[2:].strip()
    elif line.startswith('- \\') or line.startswith('  - \\'):
        domain = line.lstrip('- \\').lstrip().rstrip('\\').rstrip()
    elif '.' in line and not line.startswith('+'):
        domain = line.strip()
    else:
        return None

    if not domain:
        return None

    if validate and not is_valid_domain(domain):
        return None

    return domain


def get_parent_domain(domain: str) -> str:
    """
    获取父域名（最后两段）

    Args:
        domain: 完整域名

    Returns:
        父域名
    """
    parts = domain.split('.')
    if len(parts) > 2:
        return '.'.join(parts[-2:])
    return domain


def remove_subdomains(domains: Set[str]) -> Set[str]:
    """
    移除子域名，只保留父域名

    Args:
        domains: 域名集合

    Returns:
        过滤后的域名集合
    """
    sorted_domains = sorted(domains, key=lambda d: d[::-1])
    result: List[str] = []
    for domain in sorted_domains:
        if not result or not domain.endswith("." + result[-1]):
            result.append(domain)
    return set(result)


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
    with open(file_name, 'r', encoding='utf-8') as f:
        for line in f:
            domain = extract_domain(line, validate=validate)
            if domain:
                domains.add(domain)

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
