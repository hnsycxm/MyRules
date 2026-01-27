import sys
import re
import asyncio
import os
from pathlib import Path
import logging
from typing import Set, Dict, List, Optional, Tuple

def extract_domain(line: str) -> Optional[str]:
    """
    从规则中提取有效域名，允许的格式为 'domain' 或 '+.domain'
    排除带有 'regexp' 的规则。
    现在支持域名后添加注释（以 # 或 ! 开头的部分）
    """
    line = line.strip()
    
    # 如果整行是以 # 或 ! 开头，则跳过（这是注释行）
    if not line or line.startswith(('payload:', '#', '!', 'DOMAIN,', 'DOMAIN-KEYWORD,', 'DOMAIN-SUFFIX,', 'IP-CIDR,', 'IP-CIDR6,')):
        return None
    
    # 检查是否包含注释，如果有则移除注释部分
    clean_line = line
    if '#' in line:
        parts = line.split('#', 1)
        clean_line = parts[0].strip()
    elif '!' in line:
        parts = line.split('!', 1)
        clean_line = parts[0].strip()
    
    if 'regexp' in clean_line.lower():  # 跳过含有 'regexp' 的行
        return None
    
    if clean_line.startswith('+.'):
        domain = clean_line[2:].strip()
    elif clean_line.startswith('- \\') or clean_line.startswith('  - \\'):
        domain = clean_line.lstrip('- \\').lstrip().rstrip('\\').rstrip()
    elif '.' in clean_line and not clean_line.startswith('+'):
        domain = clean_line.strip()
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

def is_valid_domain(domain: str) -> bool:
    """
    验证域名格式是否有效
    """
    if not domain or len(domain) > 253:
        return False
    
    # 检查是否以点结尾
    if domain.endswith('.'):
        domain = domain[:-1]
    
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

    # 初始化日志
    log_entries = []
    
    try:
        # 读取原文件内容以保留注释信息
        with open(file_name, 'r', encoding='utf8') as f:
            original_lines = f.readlines()
        
        log_entries.append(f"读取到 {len(original_lines)} 行原始数据")
        
        # 解析每一行，提取域名并保存注释映射
        domain_comments: Dict[str, str] = {}
        skipped_lines: List[str] = []
        invalid_domains: List[str] = []
        
        for i, line in enumerate(original_lines, 1):
            line_stripped = line.strip()
            if line_stripped and not line_stripped.startswith(('#', '!', 'payload:', 'DOMAIN,', 'DOMAIN-KEYWORD,', 'DOMAIN-SUFFIX,', 'IP-CIDR,', 'IP-CIDR6,')):
                # 提取域名和可能的注释
                extracted_domain = extract_domain(line_stripped)
                if extracted_domain:
                    # 提取注释部分
                    comment = ''
                    if '#' in line_stripped:
                        parts = line_stripped.split('#', 1)
                        comment = ' # ' + parts[1].strip()
                    elif '!' in line_stripped:
                        parts = line_stripped.split('!', 1)
                        comment = ' ! ' + parts[1].strip()
                    
                    domain_comments[extracted_domain] = comment
                    log_entries.append(f"第{i}行成功提取域名: {extracted_domain}{comment}")
                else:
                    invalid_domains.append(f"第{i}行: {line_stripped}")
                    log_entries.append(f"第{i}行无法提取域名: {line_stripped}")
            else:
                if line_stripped:  # 如果是注释行或特殊格式行
                    skipped_lines.append(f"第{i}行: {line_stripped}")
                    log_entries.append(f"第{i}行被跳过（注释或特殊格式）: {line_stripped}")
        
        # 记录原始域名数量
        original_domains_count = len(domain_comments)
        log_entries.append(f"初步提取到 {original_domains_count} 个域名")
        
        # 提取所有域名
        domains = set(domain_comments.keys())

        # 移除子域名，保留父域名
        filtered_domains = remove_subdomains(domains)
        
        # 记录被过滤的域名
        removed_domains = domains - filtered_domains
        if removed_domains:
            for removed in removed_domains:
                log_entries.append(f"因子域名冗余被移除: {removed}")
        
        # 排序规则：按父域名和子域名排序
        sorted_domains = sorted(filtered_domains)

        # 生成两个输出文件：
        # 1. 原始文件：只包含纯净域名（用于Mihomo转换）
        with open(file_name, 'w', encoding='utf8') as f:
            for domain in sorted_domains:
                f.write(f"{domain}\n")
        
        # 2. 带注释的版本（用于人类阅读）：创建一个额外的带注释文件
        base_name = os.path.basename(file_name).rsplit('.', 1)[0]  # 获取文件名（去掉扩展名）
        annotated_file_name = f"../{base_name}_annotated.txt"
        with open(annotated_file_name, 'w', encoding='utf8') as f:
            for domain in sorted_domains:
                comment = domain_comments.get(domain, '')
                f.write(f"{domain}{comment}\n")
        
        # 生成日志文件
        log_base_name = os.path.basename(file_name).rsplit('.', 1)[0]  # 获取文件名（去掉扩展名）
        log_filename = f"../{log_base_name}_processing.log"
        with open(log_filename, 'w', encoding='utf8') as f:
            f.write("域名处理日志\n")
            f.write("=" * 50 + "\n")
            for entry in log_entries:
                f.write(entry + "\n")
            
            f.write("\n" + "=" * 50 + "\n")
            f.write(f"统计信息:\n")
            f.write(f"- 原始行数: {len(original_lines)}\n")
            f.write(f"- 初始提取域名数: {original_domains_count}\n")
            f.write(f"- 最终保留域名数: {len(sorted_domains)}\n")
            f.write(f"- 被移除域名数: {len(removed_domains)}\n")
            if skipped_lines:
                f.write("\n被跳过的行:\n")
                for line_info in skipped_lines:
                    f.write(f"  {line_info}\n")
            if invalid_domains:
                f.write("\n无效域名行:\n")
                for line_info in invalid_domains:
                    f.write(f"  {line_info}\n")

        print(f"处理完成，生成的规则总数为：{len(sorted_domains)}")
        print(f"已生成带注释的版本：{annotated_file_name}")
        print(f"已生成处理日志：{log_filename}")
    except IOError as e:
        print(f"文件操作错误: {e}")
    except Exception as e:
        print(f"处理过程中发生错误: {e}")

if __name__ == "__main__":
    asyncio.run(main())
