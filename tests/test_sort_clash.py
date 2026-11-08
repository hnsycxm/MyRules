# -*- coding: utf-8 -*-
"""sort-clash.py：行解析、规范化、Mihomo 通配语义归并、配置、原子写入。"""
import importlib
import os
import sys

import pytest
import yaml

from conftest import ROOT, SCRIPT_DIR

# --------------------------------------------------------------------------- split_rule


@pytest.mark.parametrize('line, expected', [
    ('example.com', ('', 'example.com')),
    ('- example.com', ('', 'example.com')),
    (r'  - \.yaml.com', ('', '.yaml.com')),  # 旧格式 "- \" 前缀被去掉
    ('- +.a.com', ('', '+.a.com')),
    ('-', None),
    ('"example.com"', ('', 'example.com')),
    ("'example.com'", ('', 'example.com')),
    ('example.com # comment', ('', 'example.com')),
    ('example.com \\', ('', 'example.com')),
    ('\ufeffexample.com', ('', 'example.com')),
    ('IP-CIDR,1.2.3.0/24,PROXY', ('IP-CIDR', '1.2.3.0/24')),
    ('IP-CIDR6,2001:db8::/32', ('IP-CIDR6', '2001:db8::/32')),
    ('DOMAIN-SUFFIX,foo.com', ('DOMAIN-SUFFIX', 'foo.com')),
    ('DOMAIN-KEYWORD,ads', ('DOMAIN-KEYWORD', 'ads')),
    ('GEOIP,CN', ('GEOIP', 'CN')),
    ('- "DOMAIN,foo.com"', ('DOMAIN', 'foo.com')),
    ('# hi', None),
    ('! comment', None),
    ('payload:', None),
    ('   ', None),
])
def test_split_rule(sort_clash, line, expected):
    assert sort_clash.split_rule(line) == expected


# --------------------------------------------------------------------------- normalize_pattern


@pytest.mark.parametrize('value, rule_type, bare_mode, expected', [
    # 裸域名：suffix 放宽成 +.，exact 保持精确
    ('example.com', '', 'suffix', '+.example.com'),
    ('example.com', '', 'exact', 'example.com'),
    # 显式写法原样保留，不受 bare_mode 影响
    ('+.example.com', '', 'suffix', '+.example.com'),
    ('.example.com', '', 'suffix', '.example.com'),
    ('*.example.com', '', 'suffix', '*.example.com'),
    ('a.*.example.com', '', 'suffix', 'a.*.example.com'),
    ('+.example.com', '', 'exact', '+.example.com'),
    ('*.example.com', '', 'exact', '*.example.com'),
    # 大小写 / 尾点 / IDN
    ('Example.COM.', '', 'suffix', '+.example.com'),
    ('中文.com', '', 'suffix', '+.xn--fiq228c.com'),
    ('中文.com', '', 'exact', 'xn--fiq228c.com'),
    # 规则类型
    ('example.com', 'DOMAIN', 'suffix', 'example.com'),
    ('example.com', 'DOMAIN-SUFFIX', 'suffix', '+.example.com'),
    ('example.com', 'DOMAIN-SUFFIX', 'exact', '+.example.com'),
    # 显式写法才允许单标签
    ('+.cn', '', 'suffix', '+.cn'),
    ('localhost', '', 'suffix', None),
    ('co.jp', '', 'suffix', '+.co.jp'),
    # 冲突/无效组合
    ('*.example.com', 'DOMAIN', 'suffix', None),
    ('*.example.com', 'DOMAIN-SUFFIX', 'suffix', None),
    ('+.example.com', 'DOMAIN', 'exact', None),
    # 脏数据
    ('1.2.3.4', '', 'suffix', None),
    ('foo@bar.com', '', 'suffix', None),
    ('example.com/path', '', 'suffix', None),
    ('foo bar.com', '', 'suffix', None),
    ('regexp:foo', '', 'suffix', None),
    ('*.*', '', 'suffix', None),
    ('\ufffdbad.com', '', 'suffix', None),  # errors='replace' 产生的坏字符
    ('g\uffffo.com', '', 'suffix', None),
])
def test_normalize_pattern(sort_clash, value, rule_type, bare_mode, expected):
    assert sort_clash.normalize_pattern(value, rule_type, bare_mode) == expected


@pytest.mark.parametrize('line, expected', [
    ('DOMAIN,foo.com', 'foo.com'),
    ('DOMAIN-SUFFIX,foo.com', '+.foo.com'),
    ('example.com', '+.example.com'),
    ('GEOIP,CN', None),            # 不支持的规则类型
    ('IP-CIDR,1.2.3.4', None),    # 不是域名规则
    ('# comment', None),
    ('payload:', None),
    ('\ufeffexample.com', '+.example.com'),
    ('foo@bar.com', None),
])
def test_extract_pattern(sort_clash, line, expected):
    assert sort_clash.extract_pattern(line) == expected


# --------------------------------------------------------------------------- 冗余归并（Mihomo 语义）


@pytest.mark.parametrize('patterns, expected', [
    # +.example.com 覆盖同主机的 exact / . / *.，也覆盖更深子域的一切
    (['+.example.com', '+.a.example.com', 'example.com',
      '.example.com', '*.example.com'], ['+.example.com']),
    # 公共后缀 co.jp 不可吸收子域，全部保留
    (['+.co.jp', '+.dmm.co.jp', '+.amazon.co.jp'],
     ['+.co.jp', '+.dmm.co.jp', '+.amazon.co.jp']),
    # .example.com 覆盖 *.example.com，但不覆盖精确 example.com
    (['.example.com', '*.example.com', 'example.com'],
     ['.example.com', 'example.com']),
    # 含通配符的非 *.D 形式不参与归并，原样保留
    (['+.example.com', '+.other.com', 'a.*.example.com'],
     ['+.example.com', '+.other.com', 'a.*.example.com']),
    # 真祖先 +.A 覆盖 D 下面的一切（即使 A 不是直接父域）
    (['+.example.com', '+.a.b.example.com', 'x.a.b.example.com'],
     ['+.example.com']),
    # 去重保持顺序
    (['+.a.com', '+.b.com', '+.a.com'], ['+.a.com', '+.b.com']),
    # 空集
    ([], []),
])
def test_remove_redundant(sort_clash, patterns, expected):
    assert sort_clash.remove_redundant(patterns) == expected


def test_find_covering_rule_star1_and_ancestor(sort_clash):
    ps = {'+.example.com', '.example.com', '*.example.com'}
    assert sort_clash.find_covering_rule('*.example.com', ps) == '+.example.com'
    assert sort_clash.find_covering_rule('x.example.com', ps) == '+.example.com'
    # 通配规则本身不会被当作吸收方
    assert sort_clash.find_covering_rule('example.com', {'*.example.com'}) is None


def test_is_public_suffix(sort_clash):
    assert sort_clash.is_public_suffix('co.jp') is True
    assert sort_clash.is_public_suffix('github.io') is True
    assert sort_clash.is_public_suffix('cn') is True            # 单标签
    assert sort_clash.is_public_suffix('example.com') is False
    assert sort_clash.can_absorb_subdomains('example.com') is True
    assert sort_clash.can_absorb_subdomains('co.jp') is False


def test_split_pattern_and_sort_key(sort_clash):
    assert sort_clash.split_pattern('+.example.com') == ('+.', 'example.com')
    assert sort_clash.split_pattern('.example.com') == ('.', 'example.com')
    assert sort_clash.split_pattern('example.com') == ('', 'example.com')
    items = ['+.b.com', 'example.com', '+.a.com']
    assert sorted(items, key=sort_clash.sort_key) == ['+.a.com', '+.b.com', 'example.com']


# --------------------------------------------------------------------------- 配置


def test_load_config_repo_defaults(sort_clash):
    cfg = sort_clash.load_config(ROOT / 'config.yaml')
    rules = cfg['rules']
    assert rules['bare_domain'] == 'suffix'
    assert rules['remove_subdomains'] is True
    assert rules['validate_domains'] is True
    assert rules['sort_domains'] is True
    assert rules['parallel_processes'] == 4


def test_load_config_missing_file_falls_back(sort_clash, tmp_path):
    cfg = sort_clash.load_config(tmp_path / 'nope.yaml')
    assert cfg['rules']['bare_domain'] == 'suffix'


def test_load_config_invalid_yaml_falls_back(sort_clash, tmp_path):
    p = tmp_path / 'bad.yaml'
    p.write_text('rules: [1, 2\n', encoding='utf-8')
    assert sort_clash.load_config(p)['rules']['bare_domain'] == 'suffix'


def test_load_config_partial_rules_get_defaults(sort_clash, tmp_path):
    p = tmp_path / 'partial.yaml'
    p.write_text('rules:\n  sort_domains: false\n', encoding='utf-8')
    rules = sort_clash.load_config(p)['rules']
    assert rules['sort_domains'] is False
    assert rules['bare_domain'] == 'suffix'   # setdefault 补齐


def test_load_config_no_pyyaml_falls_back(sort_clash, tmp_path, monkeypatch):
    monkeypatch.setattr(sort_clash, 'yaml', None)
    cfg = sort_clash.load_config(ROOT / 'config.yaml')
    assert cfg['rules']['bare_domain'] == 'suffix'


@pytest.mark.parametrize('config_val, override, expected', [
    ({}, None, 'suffix'),
    ({'bare_domain': 'exact'}, None, 'exact'),
    ({'bare_domain': 'exact'}, 'suffix', 'suffix'),   # 命令行优先
    ({'bare_domain': 'bogus'}, None, 'suffix'),       # 非法值回退
    ({}, 'exact', 'exact'),
])
def test_resolve_bare_mode(sort_clash, config_val, override, expected):
    assert sort_clash.resolve_bare_mode(config_val, override) == expected


# --------------------------------------------------------------------------- 终端编码 / 原子写入


def test_ensure_utf8_stdio(sort_clash):
    """非 UTF-8 终端下也不抛异常；调用后流编码为 utf-8。"""
    sort_clash.ensure_utf8_stdio()
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            assert stream.encoding.lower() in ('utf-8', 'utf8')


def test_write_lines_atomic(sort_clash, tmp_path):
    p = tmp_path / 'out.txt'
    p.write_text('old', encoding='utf-8')
    sort_clash.write_lines_atomic(str(p), ['+.b.com', '+.a.com'])
    assert p.read_text(encoding='utf-8') == '+.b.com\n+.a.com\n'
    assert not list(tmp_path.glob('*.tmp.*'))     # 临时文件已清理


# --------------------------------------------------------------------------- process_domains 原地改写


def test_process_domains_inplace(sort_clash, tmp_path):
    p = tmp_path / 'dom.txt'
    p.write_text(
        'example.com\n# comment\n*.example.com\nGEOIP,CN\n1.2.3.4\npayload:\n',
        encoding='utf-8',
    )
    count = sort_clash.process_domains(
        str(p), sort_clash.load_config(ROOT / 'config.yaml')['rules'], 'exact',
    )
    assert count == 2
    assert p.read_text(encoding='utf-8') == '*.example.com\nexample.com\n'


def test_process_domains_suffix_merges(sort_clash, tmp_path):
    """suffix 下裸父域会归并掉同域所有子规则（语义正确但反直觉，需有测试锁定）。"""
    p = tmp_path / 'dom.txt'
    p.write_text('example.com\na.example.com\n*.example.com\n', encoding='utf-8')
    count = sort_clash.process_domains(
        str(p), sort_clash.load_config(ROOT / 'config.yaml')['rules'], 'suffix',
    )
    assert count == 1
    assert p.read_text(encoding='utf-8') == '+.example.com\n'


def test_process_domains_no_sort_keeps_order(sort_clash, tmp_path):
    p = tmp_path / 'dom.txt'
    p.write_text('b.com\na.com\n', encoding='utf-8')
    rules = dict(sort_clash.load_config(ROOT / 'config.yaml')['rules'])
    rules['sort_domains'] = False
    rules['remove_subdomains'] = False
    sort_clash.process_domains(str(p), rules, 'exact')
    assert p.read_text(encoding='utf-8') == 'b.com\na.com\n'
