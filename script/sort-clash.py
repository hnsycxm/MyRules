import sys
import re
import asyncio
import os
import ipaddress

# 严格的域名正则表达式
DOMAIN_PATTERN = re.compile(r'^([a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$', re.IGNORECASE)

def is_ip(address):
    """检测是否为 IP 地址以进行剔除"""
    try:
        ipaddress.ip_address(address)
        return True
    except ValueError:
        return False

def extract_domain(line):
    """提取并规范化域名条目"""
    line = line.strip()
    if not line or line.startswith(('#', '!', '//')) or 'regexp' in line:
        return None
    
    # 移除前缀 (如 DOMAIN, 或 +.)
    clean = re.sub(r'^(DOMAIN(-SUFFIX|-KEYWORD)?|IP-CIDR6?|payload:|\+\.|-\s+|[\s\-\\]+)', '', line, flags=re.IGNORECASE)
    domain = clean.split('#')[0].split()[0].strip().strip('.').lower()

    if domain and not is_ip(domain) and DOMAIN_PATTERN.match(domain):
        return domain
    return None

def remove_subdomains(domains):
    """通过层级排序高效合并子域名"""
    if not domains: return set()
    # 核心：按域名层级倒序排列，如 ['example.com', 'www.example.com']
    sorted_domains = sorted(domains, key=lambda d: d.split('.')[::-1])
    
    result = []
    last_domain = None
    for domain in sorted_domains:
        if last_domain is None or not domain.endswith("." + last_domain):
            result.append(domain)
            last_domain = domain
    return set(result)

async def main():
    if len(sys.argv) < 2: return
    file_path = sys.argv[1]
    
    all_domains = set()
    with open(file_path, 'r', encoding='utf8', errors='ignore') as f:
        for line in f:
            d = extract_domain(line)
            if d: all_domains.add(d)

    filtered = remove_subdomains(all_domains)
    with open(file_path, 'w', encoding='utf8') as f:
        f.writelines(f"{d}\n" for d in sorted(list(filtered)))

    print(f"Processed {file_path}: {len(all_domains)} -> {len(filtered)}")

if __name__ == "__main__":
    asyncio.run(main())
