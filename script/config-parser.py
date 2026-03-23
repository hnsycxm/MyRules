#!/usr/bin/env python3
"""
配置文件解析器
支持从 config.yaml 读取配置并生成环境变量
"""

import yaml
import os
import sys
from pathlib import Path

def load_config(config_path="config.yaml"):
    """
    加载配置文件
    """
    config_file = Path(config_path)
    if not config_file.exists():
        print(f"配置文件不存在: {config_path}")
        print("使用默认配置")
        return get_default_config()

    try:
        with open(config_file, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
            return config
    except Exception as e:
        print(f"加载配置文件失败: {e}")
        print("使用默认配置")
        return get_default_config()

def get_default_config():
    """
    获取默认配置
    """
    return {
        'global': {
            'timezone': 'Asia/Shanghai',
            'log_level': 'info'
        },
        'rules': {
            'remove_subdomains': True,
            'validate_domains': True,
            'sort_domains': True,
            'parallel_processes': 4
        },
        'mihomo': {
            'download_source': 'github',
            'version_channel': 'Prerelease-Alpha',
            'timeout': 300
        },
        'output': {
            'keep_temp_files': False,
            'add_version_info': True,
            'formats': ['mrs']
        }
    }

def export_env_vars(config):
    """
    将配置导出为环境变量
    """
    env_vars = {}

    # 全局设置
    env_vars['TZ'] = config['global']['timezone']
    env_vars['LOG_LEVEL'] = config['global']['log_level']

    # 规则处理设置
    env_vars['REMOVE_SUBDOMAINS'] = str(config['rules']['remove_subdomains']).lower()
    env_vars['VALIDATE_DOMAINS'] = str(config['rules']['validate_domains']).lower()
    env_vars['SORT_DOMAINS'] = str(config['rules']['sort_domains']).lower()
    env_vars['PARALLEL_PROCESSES'] = str(config['rules']['parallel_processes'])

    # Mihomo 工具设置
    env_vars['MIHOMO_SOURCE'] = config['mihomo']['download_source']
    env_vars['MIHOMO_VERSION'] = config['mihomo']['version_channel']
    env_vars['MIHOMO_TIMEOUT'] = str(config['mihomo']['timeout'])

    # 输出设置
    env_vars['KEEP_TEMP_FILES'] = str(config['output']['keep_temp_files']).lower()
    env_vars['ADD_VERSION_INFO'] = str(config['output']['add_version_info']).lower()
    env_vars['OUTPUT_FORMATS'] = ','.join(config['output']['formats'])

    return env_vars

def print_env_exports(env_vars):
    """
    打印环境变量导出语句（用于 Bash）
    """
    for key, value in env_vars.items():
        print(f"export {key}={value}")

if __name__ == "__main__":
    config = load_config()
    env_vars = export_env_vars(config)
    print_env_exports(env_vars)
