import sys
import re
import asyncio
import os
import ipaddress

# 预编译正则：遵循 RFC 标准的域名校验
# 1. 确保每一级标签不超过 63 字符
# 2. 确保顶级域名 (TLD) 为 2-63 位字母
DOMAIN_PATTERN = re.compile(
    r'^([a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$', 
    re.IGNORECASE
)

def is_ip(address):
    """判断字符串是否为 IP 地址（IPv4 或 IPv6）"""
    try:
        ipaddress.ip_address(address)
        return True
    except ValueError:
        return False

def extract_domain(line):
    """
    清洗并规范化行数据，提取核心域名
    """
    line = line.strip()
    # 过滤注释行、空行及正则规则
    if not line or line.startswith(('#', '!', '//')) or 'regexp' in line:
        return None
    
    # 移除常见的规则前缀及干扰符
    # 支持格式：DOMAIN,example.com / +.example.com / - example.com
    clean_line = re.sub(
        r'^(DOMAIN(-SUFFIX|-KEYWORD)?|IP-CIDR6?|payload:|\+\.|-\s+|[\s\-\\]+)', 
        '', 
        line, 
        flags=re.IGNORECASE
    )
    
    # 截取空格或注释前的部分并转为小写
    domain = clean_line.split('#')[0].split()[0].strip().strip('.')
    domain = domain.lower()

    # 验证：非空、非 IP 且符合域名格式正则
    if domain and not is_ip(domain) and DOMAIN_PATTERN.match(domain):
        return domain
    return None

def remove_subdomains(domains):
    """
    核心去重逻辑：移除子域名，仅保留最上级父域名
    例如：存在 'baidu.com' 时，自动移除 'www.baidu.com'
    """
    if not domains:
        return set()
        
    # 按域名层级倒序排序：先排 TLD，再排一级域名，最后是子域名
    # 结果示例：['baidu.com', 'www.baidu.com', 'google.com']
    sorted_domains = sorted(domains, key=lambda d: d.split('.')[::-1])
    
    result = []
    last_domain = None
    
    for domain in sorted_domains:
        if last_domain is None:
            result.append(domain)
            last_domain = domain
            continue
        
        # 判断当前域名是否为上一个域名的子域名
        # 逻辑：www.baidu.com 是否以 .baidu.com 结尾
        if not domain.endswith("." + last_domain):
            result.append(domain)
            last_domain = domain
            
    return set(result)

async def process_chunk(chunk):
    """异步处理行数据块"""
    domains = set()
    for line in chunk:
        d = extract_domain(line)
        if d:
            domains.add(d)
    return domains

async def read_lines(file_path):
    """异步流式读取文件，增加容错性"""
    # 使用 errors='ignore' 防止非 UTF-8 字符阻塞构建
    with open(file_path, 'r', encoding='utf8', errors='ignore') as f:
        while True:
            # 每次读取 20000 行，平衡内存与 I/O 速度
            lines = f.readlines(20000) 
            if not lines:
                break
            yield lines

async def main():
    if len(sys.argv) < 2:
        print("Usage: python sort-clash.py <file_path>")
        return

    file_path = sys.argv[1]
    if not os.path.isfile(file_path):
        print(f"Error: {file_path} not found.")
        return

    try:
        all_domains = set()
        async for chunk in read_lines(file_path):
            chunk_domains = await process_chunk(chunk)
            all_domains.update(chunk_domains)

        # 执行子域名合并优化
        filtered_domains = remove_subdomains(all_domains)
        
        # 最终输出按字母序排列
        final_list = sorted(list(filtered_domains))

        with open(file_path, 'w', encoding='utf8') as f:
            f.writelines(f"{d}\n" for d in final_list)

        print(f"✅ 处理成功 {file_path}: 原始 {len(all_domains)} -> 优化后 {len(final_list)} 条。")

    except Exception as e:
        print(f"❌ 运行错误: {e}")

if __name__ == "__main__":
    asyncio.run(main())
