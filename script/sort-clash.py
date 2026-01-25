import sys
import re
import asyncio
import os
from pathlib import Path

def extract_domain(line):
    """
    从规则中提取有效域名，允许的格式为 'domain' 或 '+.domain'
    排除带有 'regexp' 的规则。
    """
    line = line.strip()
    if 'regexp' in line:  # 跳过含有 'regexp' 的行
        return None
    if not line or line.startswith((
        'payload:', '#', '!', 'DOMAIN,', 'DOMAIN-KEYWORD,',
        'DOMAIN-SUFFIX,', 'IP-CIDR,', 'IP-CIDR6,'
    )):
        return None
    if line.startswith('+.'):
        domain = line[2:].strip()
    elif line.startswith('- \\') or line.startswith('  - \\'):
        domain = line.lstrip('- \\').lstrip().rstrip('\\').rstrip()
    elif '.' in line and not line.startswith('+'):
        domain = line.strip()
    else:
        return None
    
    # 验证域名格式
    if domain and is_valid_domain(domain):
        return domain
    return None

def get_parent_domain(domain):
    """
    获取父域名
    """
    parts = domain.split('.')
    if len(parts) > 2:
        return '.'.join(parts[-2:])
    return domain

async def process_chunk(chunk):
    """
    异步处理文件块，提取域名规则
    """
    domains = set()
    for line in chunk:
        domain = extract_domain(line)
        if domain:
            domains.add(domain)
    return domains

async def read_lines(file_path):
    """
    异步逐行读取文件
    """
    with open(file_path, 'r', encoding='utf8') as f:
        while True:
            lines = f.readlines(10000)  # 每次读取 10KB
            if not lines:
                break
            yield lines

def is_valid_domain(domain):
    """
    验证域名格式是否有效
    """
    if not domain or len(domain) > 253:
        return False
    
    # 域名标签最大长度为63个字符
    labels = domain.split('.')
    if any(len(label) > 63 for label in labels):
        return False
    
    # 检查域名格式
    pattern = re.compile(r'^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*$')
    return bool(pattern.match(domain))


def remove_subdomains(domains):
    """
    移除子域名，只保留父域名
    """
    sorted_domains = sorted(domains, key=lambda d: d[::-1])  # 按域名倒序排序
    result = []
    for domain in sorted_domains:
        if not result or not domain.endswith("." + result[-1]):  # 当前域名不是上一个域名的子域名
            result.append(domain)
    return set(result)

async def main():
    if len(sys.argv) < 2:
        print("请提供输入文件路径作为参数")
        return

    file_name = sys.argv[1]
    
    # 检查文件是否存在
    if not os.path.exists(file_name):
        print(f"错误：文件 {file_name} 不存在")
        return
    
    if not os.path.isfile(file_name):
        print(f"错误：{file_name} 不是一个有效的文件")
        return

    try:
        # 按块处理文件
        domains = set()

        async for chunk in read_lines(file_name):
            chunk_domains = await process_chunk(chunk)
            domains.update(chunk_domains)

        # 移除子域名，保留父域名
        filtered_domains = remove_subdomains(domains)

        # 排序规则：按父域名和子域名排序
        sorted_domains = sorted(filtered_domains)

        # 写入文件
        with open(file_name, 'w', encoding='utf8') as f:
            f.writelines(f"{domain}\n" for domain in sorted_domains)

        print(f"处理完成，生成的规则总数为：{len(sorted_domains)}")
    except IOError as e:
        print(f"文件操作错误: {e}")
    except Exception as e:
        print(f"处理过程中发生错误: {e}")

if __name__ == "__main__":
    asyncio.run(main())
