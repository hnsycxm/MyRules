# sort-clash.py (保持原文件名)
import sys
import re
import os
from typing import Set, List

def is_valid_domain(domain: str) -> bool:
    """验证域名格式是否有效"""
    if not domain or len(domain) > 253:
        return False
    
    # 移除末尾的点
    if domain.endswith('.'):
        domain = domain[:-1]
    
    # 检查域名标签长度
    labels = domain.split('.')
    if any(len(label) > 63 for label in labels):
        return False
    
    # 检查域名格式
    pattern = re.compile(r'^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*$')
    return bool(pattern.match(domain))

def extract_domain(line: str) -> str:
    """从行中提取域名"""
    line = line.strip()
    if not line or line.startswith(('#', '!', 'DOMAIN,', 'DOMAIN-KEYWORD,', 'DOMAIN-SUFFIX,', 'IP-CIDR,', 'IP-CIDR6,', 'payload:')):
        return None
    
    # 移除注释部分
    if '#' in line:
        line = line.split('#', 1)[0].strip()
    elif '!' in line:
        line = line.split('!', 1)[0].strip()
    
    if 'regexp' in line.lower():
        return None
    
    # 处理不同格式的域名
    if line.startswith('+.'):
        domain = line[2:].strip()
    elif line.startswith('- \\') or line.startswith('  - \\'):
        domain = line.lstrip('- \\').lstrip().rstrip('\\').rstrip()
    elif '.' in line and not line.startswith(('DOMAIN', 'IP-CIDR')):
        domain = line.strip()
    else:
        return None
    
    return domain if is_valid_domain(domain) else None

def remove_subdomains(domains: Set[str]) -> Set[str]:
    """移除子域名，只保留父域名"""
    sorted_domains = sorted(domains, key=lambda d: d[::-1])
    result = []
    for domain in sorted_domains:
        is_subdomain = False
        for parent in result:
            if domain.endswith('.' + parent):
                is_subdomain = True
                break
        if not is_subdomain:
            result.append(domain)
    return set(result)

def main():
    if len(sys.argv) < 2:
        print("请提供输入文件路径作为参数")
        return

    file_path = sys.argv[1]
    
    if not os.path.exists(file_path):
        print(f"错误：文件 {file_path} 不存在")
        return

    # 读取并处理域名
    domains = set()
    with open(file_path, 'r', encoding='utf8') as f:
        for line_num, line in enumerate(f, 1):
            domain = extract_domain(line)
            if domain:
                domains.add(domain)
    
    # 移除子域名
    filtered_domains = remove_subdomains(domains)
    
    # 按字母顺序排序
    sorted_domains = sorted(filtered_domains)
    
    # 写回原文件
    with open(file_path, 'w', encoding='utf8') as f:
        for domain in sorted_domains:
            f.write(f"{domain}\n")
    
    print(f"处理完成，最终保留域名数：{len(sorted_domains)}")

if __name__ == "__main__":
    main()
