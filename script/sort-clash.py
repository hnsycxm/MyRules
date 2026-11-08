#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Mihomo domain 规则集清洗脚本：规范化、去重、冗余归并、排序（原地改写文件）。

用法：
    python sort-clash.py <文件> [--config <config.yaml>] [--bare-domain suffix|exact]

输出的每一行都是 Mihomo「domain 规则集」（behavior: domain）合法的通配写法，
语义严格遵循 Mihomo 官方文档「Domain Wildcards」：

    example.com      仅匹配 example.com（精确）
    *.example.com    仅匹配一级子域；不含 example.com，也不含 a.b.example.com
    .example.com     匹配任意级子域；不含 example.com
    +.example.com    匹配 example.com 及其所有子域（等价于 DOMAIN-SUFFIX）
    a.*.example.com  标签位置的 * 匹配恰好一级；"+" 与 "." 只能出现在最前面

核心原则：显式写法绝不改写语义（不会把 *.x、.x、精确域名偷偷放宽成 +.x）。
唯一需要约定的是「裸域名」：Mihomo 原生语义是精确匹配，但本项目的历史约定是把
裸域名当作后缀，因此由 rules.bare_domain（或 --bare-domain）决定：
    suffix（默认，沿用历史行为）：裸域名 → +.域名
    exact（Mihomo 原生语义）   ：裸域名 → 域名本身
带通配符的裸写法（如 *.x、a.*.x）按 Mihomo 语义原样保留，不受该选项影响。

本模块同时被 classify-rules.py 以 importlib 方式复用，两个脚本需放在同一目录。

环境变量：
    MYRULES_VERBOSE=1   打印每一条被归并掉的规则
"""

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

# PyYAML 是唯一的外部依赖：缺失时回退到默认配置，而不是让构建整体失败
try:
    import yaml
except ImportError:  # pragma: no cover - 取决于运行环境
    yaml = None  # type: ignore[assignment]

# 多段公共后缀（不完整的 PSL 子集）。
# 作用：当清单里写了 "+.co.jp" 这类过宽的父域时，不用它去归并
# "dmm.co.jp"、"amazon.co.jp" 等真实域名（只是少做一次优化，语义不受影响）。
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
    'com.vn', 'com.pk', 'com.ng', 'com.eg', 'com.sa', 'com.ua', 'com.pl',
    'com.ru', 'com.co', 'com.pe',
    'co.kr', 'or.kr', 'ne.kr', 'go.kr', 're.kr',
    'co.nz', 'co.za', 'co.in', 'co.id', 'co.th', 'co.il', 'co.ke',
    'org.in', 'net.in', 'ac.in', 'gov.in',
    # 托管平台（常见于规则清单）
    'github.io', 'gitee.io', 'gitlab.io', 'pages.dev', 'workers.dev',
    'vercel.app', 'netlify.app', 'herokuapp.com', 'blogspot.com',
    'cloudfront.net', 'azurewebsites.net', 'appspot.com',
})

# 整行忽略（注释 / Clash payload 头）
IGNORED_PREFIXES: Tuple[str, ...] = ('#', '!', 'payload:')

# 本脚本能无损转换为 domain 规则集写法的 Clash 规则类型
#   DOMAIN         → 精确匹配（裸域名）
#   DOMAIN-SUFFIX  → +.域名
# DOMAIN-KEYWORD / DOMAIN-REGEX / DOMAIN-WILDCARD 无法用 domain 规则集等价表达，不支持。
DOMAIN_RULE_TYPES: Tuple[str, ...] = ('DOMAIN', 'DOMAIN-SUFFIX')

BARE_SUFFIX = 'suffix'
BARE_EXACT = 'exact'
BARE_MODES: Tuple[str, ...] = (BARE_SUFFIX, BARE_EXACT)


# --------------------------------------------------------------------------- 终端编码
def ensure_utf8_stdio() -> None:
    """
    保证 stdout / stderr 在非 UTF-8 终端下输出中文与 emoji 时不会抛 UnicodeEncodeError。

    背景：本脚本的日志含 ✅ / ⚠️ / ❌ 等字符，中文 Windows 的 GBK 控制台无法编码，
    旧版本会因此在最后一行 print 抛异常、以非 0 退出，而此时域名文件其实已正确
    写出，导致 build-combined-rules.sh 把一次成功的清洗误判为失败。

    统一改为 UTF-8 输出：终端编码不匹配时日志可能显示为乱码，但绝不会崩溃，
    退出码与产物保持正确。errors='backslashreplace' 作为极端情况下的第二重兜底。
    classify-rules.py 复用本函数，两个入口行为一致。
    """
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, 'reconfigure', None)  # Python 3.7+
        if reconfigure is None:
            continue
        try:
            reconfigure(encoding='utf-8', errors='backslashreplace')
        except (ValueError, OSError):  # pragma: no cover - 取决于运行环境
            pass


# 标签字符集：字母、数字、连字符、下划线；连字符不能在首尾。
# Mihomo 本身只校验结构（无空标签、无结尾的点），不限制字符集，这里取常见合法集合以过滤脏数据。
_LABEL_RE = re.compile(r'[a-z0-9_]([a-z0-9_-]*[a-z0-9_])?')
_INLINE_COMMENT_RE = re.compile(r'\s+#.*$')
_RULE_TYPE_RE = re.compile(r'[A-Za-z][A-Za-z0-9-]*')


# --------------------------------------------------------------------------- 配置
def load_config(config_path: Optional[Path] = None) -> Dict[str, Any]:
    """加载配置文件；任何问题都回退到默认配置（警告走 stderr，不污染 stdout）。"""
    default_config: Dict[str, Any] = {
        'rules': {
            'remove_subdomains': True,
            'validate_domains': True,
            'sort_domains': True,
            'bare_domain': BARE_SUFFIX,
        }
    }

    if config_path is None:
        config_path = Path(__file__).resolve().parent.parent / 'config.yaml'

    if not config_path.exists():
        print(f"警告：配置文件不存在 {config_path}，使用默认配置", file=sys.stderr)
        return default_config

    if yaml is None:
        print("警告：未安装 PyYAML（pip install pyyaml），使用默认配置", file=sys.stderr)
        return default_config

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
    except Exception as exc:
        print(f"警告：加载配置文件失败 {exc}，使用默认配置", file=sys.stderr)
        return default_config

    if not isinstance(config, dict):
        print("警告：配置文件格式错误，使用默认配置", file=sys.stderr)
        return default_config

    rules = config.get('rules')
    if not isinstance(rules, dict):
        config['rules'] = dict(default_config['rules'])
    else:
        for key, value in default_config['rules'].items():
            rules.setdefault(key, value)
    return config


def resolve_bare_mode(rules_config: Dict[str, Any], override: Optional[str] = None) -> str:
    """裸域名的解释方式：命令行参数优先，其次 rules.bare_domain，默认 suffix。"""
    mode = override or rules_config.get('bare_domain', BARE_SUFFIX)
    if mode not in BARE_MODES:
        print(f"警告：bare_domain={mode!r} 无效（可选 suffix / exact），回退为 {BARE_SUFFIX}", file=sys.stderr)
        return BARE_SUFFIX
    return mode


# --------------------------------------------------------------------------- 行解析
def split_rule(line: str) -> Optional[Tuple[str, str]]:
    """
    把一行拆成 (规则类型, 值)。

    返回 None 表示这一行应被忽略（空行、注释、payload:）。
    规则类型为空串表示「裸条目」（裸域名、+.domain、IP 等）。
    会处理：BOM、YAML 列表项（"- "、旧格式 "- \\"）、外层引号、
    行尾续行反斜杠、行内 "# 注释"、Clash 规则（TYPE,value[,policy]）。
    """
    line = line.replace('\ufeff', '').strip()
    if not line or line.startswith(IGNORED_PREFIXES):
        return None

    if line.startswith('- \\'):
        line = line[3:].strip()
    elif line.startswith('- '):
        line = line[2:].strip()
    elif line == '-':
        return None
    if line.startswith(IGNORED_PREFIXES):
        return None

    line = _INLINE_COMMENT_RE.sub('', line).strip()
    if line.endswith('\\'):
        line = line[:-1].strip()
    if len(line) >= 2 and line[0] == line[-1] and line[0] in '\'"':
        line = line[1:-1].strip()
    if not line:
        return None

    head, sep, rest = line.partition(',')
    head = head.strip()
    if sep and _RULE_TYPE_RE.fullmatch(head):
        return head.upper(), rest.split(',')[0].strip()
    return '', line


def _valid_host(host: str, allow_wildcard: bool, allow_single_label: bool) -> bool:
    """
    校验去掉 "+." / "." 前缀后的主机部分。

    结构要求对齐 Mihomo：无空标签、无结尾的点；* 只能独占一个标签（a*b 这种写法
    在 Mihomo 里会被当成字面量、永远匹配不到，因此拒绝）。
    另外要求至少有一个字面标签，防止 "*.*" 这种匹配一切的规则。
    """
    if not host or len(host) > 253:
        return False

    labels = host.split('.')
    if len(labels) < 2 and not allow_single_label:
        return False

    literal = 0
    for label in labels:
        if label == '*':
            if not allow_wildcard:
                return False
            continue
        if not label or len(label) > 63 or not _LABEL_RE.fullmatch(label):
            return False
        literal += 1
    if literal == 0:
        return False

    last = labels[-1]
    if last != '*' and (last.isdigit() or (len(labels) >= 2 and len(last) < 2)):
        return False  # 拒绝纯数字 TLD（如 IPv4 地址）与一位 TLD
    return True


def normalize_pattern(
    value: str,
    rule_type: str = '',
    bare_mode: str = BARE_SUFFIX,
    validate: bool = True,
) -> Optional[str]:
    """
    把「值」规范化为一条 Mihomo domain 规则集写法；无效返回 None。

    规范化：小写、IDN 转 punycode、去结尾的点（Mihomo 不接受结尾的点）。
    语义：显式前缀（+. / .）与通配符原样保留；DOMAIN-SUFFIX → "+."；
    DOMAIN → 精确；不带前缀与通配符的裸域名按 bare_mode 处理。
    """
    value = value.strip()
    if not value or any(ch.isspace() for ch in value):
        return None
    if value.lower().startswith(('regexp:', 'regex:')):
        return None

    prefix = ''
    if value.startswith('+.'):
        prefix, value = '+.', value[2:]
    elif value.startswith('.'):
        prefix, value = '.', value[1:]
    host = value.rstrip('.')
    if not host:
        return None

    if not host.isascii():
        try:
            host = host.encode('idna').decode('ascii')
        except UnicodeError:
            return None
    host = host.lower()
    wildcard = '*' in host
    # 显式写法（带前缀或带规则类型）才允许单标签，如 "+.cn"；裸的单个单词视为脏数据
    explicit = bool(prefix) or rule_type != ''

    if rule_type == 'DOMAIN-SUFFIX':
        if prefix == '.' or wildcard:
            return None
        prefix = '+.'
    elif rule_type == 'DOMAIN':
        if prefix or wildcard:
            return None
    elif not prefix and not wildcard:
        prefix = '+.' if bare_mode == BARE_SUFFIX else ''

    if validate and not _valid_host(host, allow_wildcard=(rule_type == ''), allow_single_label=explicit):
        return None
    return prefix + host


def extract_pattern(line: str, bare_mode: str = BARE_SUFFIX, validate: bool = True) -> Optional[str]:
    """从一行规则中提取 domain 规则集写法；不是域名规则（或类型不受支持）返回 None。"""
    parsed = split_rule(line)
    if parsed is None:
        return None
    rule_type, value = parsed
    if rule_type != '' and rule_type not in DOMAIN_RULE_TYPES:
        return None
    return normalize_pattern(value, rule_type, bare_mode, validate)


# --------------------------------------------------------------------------- 冗余归并
def split_pattern(pattern: str) -> Tuple[str, str]:
    """把规则写法拆成 (前缀, 主机)；前缀为 "+." / "." / ""。"""
    if pattern.startswith('+.'):
        return '+.', pattern[2:]
    if pattern.startswith('.'):
        return '.', pattern[1:]
    return '', pattern


def is_public_suffix(domain: str) -> bool:
    """是否为已知的多段公共后缀（如 co.jp）或单标签。"""
    return '.' not in domain or domain.lower() in MULTI_PART_PUBLIC_SUFFIXES


def can_absorb_subdomains(domain: str) -> bool:
    """普通父域（example.com）可以吸收更深层的规则；公共后缀（co.jp）不可以。"""
    return not is_public_suffix(domain)


def find_covering_rule(pattern: str, pattern_set: "set") -> Optional[str]:
    """
    若 `pattern` 的匹配范围完全落在集合里另一条规则之内，返回那条规则，否则返回 None。

    按 Mihomo 语义判断（D 为该规则的主机，A 为 D 的真祖先）：
      * +.A 与 .A 都覆盖 D 下面的一切：精确 D、+.D、.D、*.D；
      * +.D 覆盖同主机的 D、.D、*.D（它们都是 +.D 的子集）；
      * .D 覆盖 *.D（任意级子域 ⊇ 一级子域）；.D 不覆盖精确的 D。
    含通配符的规则只有 *.D 这一种形式参与归并，其余通配规则原样保留，
    且任何含 * 的规则都不会被当作「吸收方」。
    """
    prefix, host = split_pattern(pattern)

    if '*' in host:
        if prefix == '' and host.startswith('*.') and '*' not in host[2:]:
            kind, base = 'star1', host[2:]
        else:
            return None
    else:
        kind, base = {'': 'exact', '+.': 'suffix', '.': 'dot'}[prefix], host

    # 同主机：+.D 覆盖 exact / dot / *.D；.D 覆盖 *.D
    if kind in ('exact', 'dot', 'star1') and ('+.' + base) in pattern_set:
        return '+.' + base
    if kind == 'star1' and ('.' + base) in pattern_set:
        return '.' + base

    # 真祖先：+.A 或 .A 覆盖 D 下面的一切
    labels = base.split('.')
    for i in range(1, len(labels)):
        ancestor = '.'.join(labels[i:])
        if not can_absorb_subdomains(ancestor):
            continue
        for candidate in ('+.' + ancestor, '.' + ancestor):
            if candidate in pattern_set:
                return candidate
    return None


def remove_redundant(patterns: Iterable[str]) -> List[str]:
    """移除被其他规则完全覆盖的规则，保持输入顺序。"""
    ordered = list(dict.fromkeys(patterns))
    pattern_set = set(ordered)
    verbose = bool(os.environ.get('MYRULES_VERBOSE'))

    kept: List[str] = []
    for pattern in ordered:
        cover = find_covering_rule(pattern, pattern_set)
        if cover is None:
            kept.append(pattern)
        elif verbose:
            print(f"  [归并] {pattern} 已被 {cover} 覆盖")
    return kept


def sort_key(pattern: str) -> Tuple[str, str]:
    """按主机排序，使同一域名的不同写法相邻。"""
    return split_pattern(pattern)[1], pattern


# --------------------------------------------------------------------------- 主流程
def write_lines_atomic(path: str, lines: Iterable[str]) -> None:
    """先写临时文件再替换，避免中途失败留下被截断的文件。"""
    tmp_path = f"{path}.tmp.{os.getpid()}"
    try:
        with open(tmp_path, 'w', encoding='utf-8', newline='\n') as f:
            f.writelines(f"{line}\n" for line in lines)
        os.replace(tmp_path, path)
    except BaseException:
        try:
            os.remove(tmp_path)
        except OSError:
            pass
        raise


def process_domains(file_name: str, rules_config: Dict[str, Any], bare_mode: str = BARE_SUFFIX) -> int:
    """处理域名文件（原地改写），返回最终规则数量。"""
    validate = bool(rules_config.get('validate_domains', True))

    # dict 去重并保持首次出现的顺序：sort_domains=false 时输出也是确定的
    seen: Dict[str, None] = {}
    dropped: List[str] = []
    # errors='replace'：坏字节会产生无效域名被丢弃，而不是被悄悄拼成另一个合法域名
    with open(file_name, 'r', encoding='utf-8-sig', errors='replace') as f:
        for line in f:
            pattern = extract_pattern(line, bare_mode, validate)
            if pattern:
                seen[pattern] = None
            elif validate and split_rule(line) is not None:
                dropped.append(line.strip())

    items = list(seen)
    unique_count = len(items)

    if rules_config.get('remove_subdomains', True):
        items = remove_redundant(items)
    merged = unique_count - len(items)

    if rules_config.get('sort_domains', True):
        items.sort(key=sort_key)

    write_lines_atomic(file_name, items)

    if dropped:
        preview = ', '.join(dropped[:5]) + (" …" if len(dropped) > 5 else "")
        print(f"⚠️ 跳过 {len(dropped)} 行无法解析为域名规则的内容：{preview}", file=sys.stderr)
    if merged:
        print(f"冗余归并：{unique_count} → {len(items)}（移除 {merged} 条）")

    return len(items)


def main() -> None:
    ensure_utf8_stdio()
    parser = argparse.ArgumentParser(description='Mihomo domain 规则集清洗（原地改写文件）')
    parser.add_argument('file', help='输入文件路径（会被原地覆盖）')
    parser.add_argument('--config', type=Path, default=None, help='配置文件路径（默认：项目根目录/config.yaml）')
    parser.add_argument(
        '--bare-domain', choices=BARE_MODES, default=None,
        help='裸域名的解释方式（默认取 rules.bare_domain，缺省 suffix）；'
             '输入已是 classify-rules.py 产出的显式写法时应传 exact',
    )
    args = parser.parse_args()

    if not os.path.isfile(args.file):
        print(f"错误：'{args.file}' 不是一个有效的文件", file=sys.stderr)
        sys.exit(1)

    config = load_config(args.config)
    rules_config = config.get('rules', {})
    bare_mode = resolve_bare_mode(rules_config, args.bare_domain)

    try:
        count = process_domains(args.file, rules_config, bare_mode)
    except OSError as exc:
        print(f"❌ 文件操作错误：{exc}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:  # noqa: BLE001 - 构建脚本需要把任何异常转成非 0 退出码
        print(f"❌ 处理过程中发生错误：{exc}", file=sys.stderr)
        sys.exit(1)

    print(f"✅ 处理完成，生成的规则总数为：{count}")


if __name__ == "__main__":
    main()
