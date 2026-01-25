import sys
import re
import asyncio
import os
from pathlib import Path

# 增加 IP/CIDR 校验正则
IPV4_PATTERN = re.compile(r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\/(3[0-2]|[12]?[0-9])?)?$')
IPV6_PATTERN = re.compile(r'^([0-9a-fA-F]{1,4}:){1,7}[0-9a-fA-F]{1,4}(\/(12[0-8]|1[01][0-9]|[1-9]?[0-9]))?$')

def extract_item(line):
    """
    提取域名或 IP 规则，允许标准格式、+.格式或包含前缀的格式
    """
    line = line.strip()
    if 'regexp' in line or not line or line.startswith(('payload:', '#', '!')):
        return None
    
    # 处理常见规则前缀，提取核心内容
    content = line
    for prefix in ['DOMAIN,', 'DOMAIN-SUFFIX,', 'DOMAIN-KEYWORD,', 'IP-CIDR,', 'IP-CIDR6,', '+.']:
        if line.startswith(prefix):
            content = line[len(prefix):].strip()
            break
    
    # 清理 YAML 列表符号
    content = content.lstrip('- \\\\').rstrip('\\\\').strip()

    # 验证是否为合法 IP 或 域名
    if content and (bool(IPV4_PATTERN.match(content)) or bool(IPV6_PATTERN.match(content)) or is_valid_domain(content)):
        return content
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
    异步处理文件块，提取域名/IP规则
    """
    items = set()
    for line in chunk:
        item = extract_item(line)
        if item:
            items.add(item)
    return items

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
        # 按块处理文件并分类存储
        raw_items = set()
        async for chunk in read_lines(file_name):
            for line in chunk:
                item = extract_item(line) # 使用新的提取函数
                if item:
                    raw_items.add(item)

        # 分类：IP 不参与子域名缩减，域名执行缩减逻辑
        ips = {i for i in raw_items if IPV4_PATTERN.match(i) or IPV6_PATTERN.match(i)}
        domains = raw_items - ips
        
        filtered_domains = remove_subdomains(domains) # 仅对域名去重优化
        final_list = sorted(list(ips) + list(filtered_domains)) # 合并后全局排序

        # 写入文件
        with open(file_name, 'w', encoding='utf8') as f:
            f.writelines(f"{item}\n" for item in final_list)

        print(f"处理完成，生成的规则总数为：{len(final_list)}")
    except IOError as e:
        print(f"文件操作错误: {e}")
    except Exception as e:
        print(f"处理过程中发生错误: {e}")

if __name__ == "__main__":
    asyncio.run(main())