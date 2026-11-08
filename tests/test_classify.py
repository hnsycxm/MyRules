# -*- coding: utf-8 -*-
"""classify-rules.py：IP 解析/网段合并、与 sort-clash.py 的契约、端到端 stdout 契约。"""
import os
import subprocess
import sys

import pytest

from conftest import ROOT, SCRIPT_DIR


# --------------------------------------------------------------------------- parse_ip


@pytest.mark.parametrize('value, expected', [
    ('1.2.3.4', '1.2.3.4/32'),
    ('1.2.3.0/24', '1.2.3.0/24'),
    ('2001:db8::1', '2001:db8::1/128'),
    ('2001:db8::/32', '2001:db8::/32'),
    ('10.0.0.5/8', '10.0.0.0/8'),        # strict=False 把主机位归零
    ('example.com', None),
    ('', None),
    ('999.999.999.999', None),
])
def test_parse_ip(classify, value, expected):
    net = classify.parse_ip(value)
    assert (str(net) if net is not None else None) == expected


# --------------------------------------------------------------------------- collapse_networks


def test_collapse_networks_groups_by_version(classify):
    """IPv4/IPv6 必须分组，否则 collapse_addresses 会抛 TypeError。"""
    nets = [classify.parse_ip(v) for v in [
        '1.2.3.4', '1.2.3.0/25', '1.2.3.128/25',
        '2001:db8::1', '2001:db8::/32',
        '10.0.0.0/8', '10.1.0.0/16',
    ]]
    result = classify.collapse_networks([n for n in nets if n])
    assert result == ['1.2.3.0/24', '10.0.0.0/8', '2001:db8::/32']
    # IPv4 在前、IPv6 在后
    assert result[0].startswith('1.') or result[0].startswith('10.')
    assert result[-1].startswith('2001:')


def test_collapse_networks_empty(classify):
    assert classify.collapse_networks([]) == []


def test_collapse_networks_dedup(classify):
    nets = [classify.parse_ip(v) for v in ['1.2.3.4', '1.2.3.4', '1.2.3.0/24']]
    assert classify.collapse_networks(nets) == ['1.2.3.0/24']


# --------------------------------------------------------------------------- 与 sort-clash.py 的契约


def test_classifier_reuses_sort_clash_module(classify):
    """分类器按路径复用 sort-clash.py，域名判定与清洗器共用同一个实现。"""
    sc = classify.load_sort_clash()
    assert sc.normalize_pattern('example.com', '', 'suffix') == '+.example.com'
    assert sc.DOMAIN_RULE_TYPES == ('DOMAIN', 'DOMAIN-SUFFIX')
    assert hasattr(sc, 'ensure_utf8_stdio')


# --------------------------------------------------------------------------- 端到端（子进程）

# 分类阶段产出的域名写法 = 规范化、去重后（尚未冗余归并）的条数
E2E_INPUT = (
    '\ufeffexample.com\n'        # 裸域名 → +.example.com
    'DOMAIN,exact.com\n'         # 显式精确
    '*.wild.com\n'               # 通配，原样保留
    'IP-CIDR,1.2.3.0/24,PROXY\n'
    '1.2.3.4\n'                 # 与上面同网段，合并后仍一条
    '2001:db8::1\n'
    'GEOIP,CN\n'                # 无法识别（mrs 无法表达）
    'DOMAIN-KEYWORD,ads\n'      # 无法识别
    'foo@bar.com\n'             # 脏数据，无法识别
    '# comment\n'               # 忽略，不计数
    'payload:\n'                # 忽略，不计数
)


def _run_classify(tmp_path, extra_env=None, config=None):
    src = tmp_path / 'in.txt'
    src.write_text(E2E_INPUT, encoding='utf-8')
    ip_out = tmp_path / 'ip.txt'
    dom_out = tmp_path / 'dom.txt'
    args = [str(SCRIPT_DIR / 'classify-rules.py'), str(src), str(ip_out), str(dom_out)]
    if config is not None:
        args += ['--config', str(config)]
    env = dict(os.environ)
    env.setdefault('PYTHONIOENCODING', 'utf-8')
    if extra_env:
        env.update(extra_env)
    proc = subprocess.run([sys.executable] + args, cwd=str(ROOT), env=env, capture_output=True)
    return proc, ip_out, dom_out


def test_e2e_stdout_contract(tmp_path):
    """stdout 严格三行整数：IP 数（合并后）、域名数、无法识别数。"""
    proc, ip_out, dom_out = _run_classify(tmp_path)
    assert proc.returncode == 0, proc.stderr.decode('utf-8', 'replace')
    lines = proc.stdout.decode('utf-8').strip().splitlines()
    assert len(lines) == 3
    assert all(line.isdigit() for line in lines), lines
    ip_n, dom_n, unknown_n = map(int, lines)
    assert ip_n == 2          # 1.2.3.0/24 + 2001:db8::1/128
    assert dom_n == 3         # +.example.com, exact.com, *.wild.com
    assert unknown_n == 3     # GEOIP / DOMAIN-KEYWORD / foo@bar.com
    # 与文件实际内容一致：修复首轮「分类数与编译数不一致」的核心回归
    assert len(ip_out.read_text(encoding='utf-8').splitlines()) == ip_n
    assert len(dom_out.read_text(encoding='utf-8').splitlines()) == dom_n
    assert ip_out.read_text(encoding='utf-8') == '1.2.3.0/24\n2001:db8::1/128\n'
    # 按 sort_clash.sort_key（按主机）排序；用集合断言内容，与顺序解耦
    assert set(dom_out.read_text(encoding='utf-8').splitlines()) == {
        'exact.com', '+.example.com', '*.wild.com'}


def test_e2e_warnings_go_to_stderr(tmp_path):
    proc, _, _ = _run_classify(tmp_path)
    stdout = proc.stdout.decode('utf-8')
    stderr = proc.stderr.decode('utf-8', 'replace')
    assert '无法识别' in stderr
    assert 'GEOIP' in stderr and 'DOMAIN-KEYWORD' in stderr
    assert '无法识别' not in stdout       # 告警不污染三行契约
    assert '⚠' in stderr or '\\u' in stderr


def test_e2e_gbk_console_exits_zero(tmp_path):
    """非 UTF-8 终端（GBK）下打印中文/emoji 告警也不得崩溃或误报失败。"""
    proc, ip_out, dom_out = _run_classify(tmp_path, extra_env={'PYTHONIOENCODING': 'gbk'})
    assert proc.returncode == 0, proc.stderr.decode('utf-8', 'replace')
    assert len(proc.stdout.decode('utf-8', 'replace').strip().splitlines()) == 3
    assert ip_out.read_text(encoding='utf-8') == '1.2.3.0/24\n2001:db8::1/128\n'


def test_e2e_config_bare_domain_exact(tmp_path):
    """config.yaml 的 bare_domain 决定裸域名解释方式，且被分类器读取。"""
    cfg = tmp_path / 'config.yaml'
    cfg.write_text('rules:\n  bare_domain: exact\n', encoding='utf-8')
    proc, _, dom_out = _run_classify(tmp_path, config=cfg)
    assert proc.returncode == 0
    dom = dom_out.read_text(encoding='utf-8')
    assert 'example.com\n' in dom
    assert '+.example.com' not in dom


def test_e2e_missing_pyyaml_falls_back(tmp_path):
    """PyYAML 缺失时仍以默认配置运行（suffix），不整体失败。"""
    cfg = tmp_path / 'config.yaml'
    cfg.write_text('rules:\n  bare_domain: exact\n', encoding='utf-8')
    # 在 PYTHONPATH 前置一个 yaml.py，import 时抛 ImportError 模拟「未安装 PyYAML」；
    # 该异常会被 sort-clash.py / classify-rules.py 的 try-except 捕获并回退默认配置。
    blocker = tmp_path / 'blocker'
    blocker.mkdir()
    (blocker / 'yaml.py').write_text('raise ImportError("simulated: PyYAML not installed")\n', encoding='utf-8')
    env = dict(os.environ)
    env['PYTHONPATH'] = str(blocker) + os.pathsep + env.get('PYTHONPATH', '')
    proc, _, dom_out = _run_classify(tmp_path, extra_env=env, config=cfg)
    assert proc.returncode == 0, proc.stderr.decode('utf-8', 'replace')
    assert 'PyYAML' in proc.stderr.decode('utf-8', 'replace')     # 打印了回退告警
    assert '+.example.com' in dom_out.read_text(encoding='utf-8')  # 回退到 suffix 默认
