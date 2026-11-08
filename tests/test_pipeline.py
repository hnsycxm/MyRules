# -*- coding: utf-8 -*-
"""端到端流水线回归：classify → sort 的契约，以及真实 txt/ 清单的健康度。"""
import os
import subprocess
import sys

import pytest

from conftest import ROOT, SCRIPT_DIR


def _parse_counts(proc):
    lines = proc.stdout.decode('utf-8', 'replace').strip().splitlines()
    assert len(lines) == 3, lines
    return tuple(int(x) for x in lines)


def test_classify_then_sort_contract(tmp_path):
    """
    分类产出的域名文件交给 sort-clash.py --bare-domain exact 后：
      - 全部行都是合法 Mihomo domain 写法（不会被丢弃）
      - 数量变化只可能来自「冗余归并」，不来自解析失败/二次放宽
      - 非 UTF-8 终端下两个脚本都以 rc=0 退出
    """
    src = tmp_path / 'in.txt'
    # 含裸域名、显式写法、通配、Clash 规则、IP、脏数据、注释
    src.write_text(
        'example.com\n'
        'DOMAIN,exact.example.com\n'
        'DOMAIN-SUFFIX,suffix.example.com\n'
        '*.wild.example.com\n'
        'a.*.mid.example.com\n'
        'IP-CIDR,10.0.0.0/8,DIRECT\n'
        '2001:db8::/32\n'
        'GEOIP,CN\n'
        '# comment\n',
        encoding='utf-8',
    )
    ip_out = tmp_path / 'ip.txt'
    dom_out = tmp_path / 'dom.txt'

    env = dict(os.environ)
    env['PYTHONIOENCODING'] = 'gbk'   # 强制非 UTF-8，验证两个入口都不崩
    base = [sys.executable]

    r1 = subprocess.run(
        base + [str(SCRIPT_DIR / 'classify-rules.py'), str(src), str(ip_out), str(dom_out),
                '--config', str(ROOT / 'config.yaml')],
        cwd=str(ROOT), env=env, capture_output=True,
    )
    assert r1.returncode == 0, r1.stderr.decode('utf-8', 'replace')
    ip_n, dom_n, unknown_n = _parse_counts(r1)
    assert unknown_n == 1                       # GEOIP,CN
    assert len(dom_out.read_text(encoding='utf-8').splitlines()) == dom_n

    before = dom_out.read_text(encoding='utf-8').splitlines()
    r2 = subprocess.run(
        base + [str(SCRIPT_DIR / 'sort-clash.py'), str(dom_out),
                '--config', str(ROOT / 'config.yaml'), '--bare-domain', 'exact'],
        cwd=str(ROOT), env=env, capture_output=True,
    )
    assert r2.returncode == 0, r2.stderr.decode('utf-8', 'replace')
    after = dom_out.read_text(encoding='utf-8').splitlines()

    # sort 阶段不应丢弃任何行：所有分类产出都是合法显式写法
    assert '跳过' not in r2.stderr.decode('utf-8', 'replace')
    # 允许减少但只来自冗余归并（这里 +.suffix.example.com 与子域会归并）
    assert len(after) <= len(before)
    assert set(after).issubset(set(before))


def test_all_txt_lists_have_zero_unrecognized(tmp_path):
    """
    守护 CI 的 STRICT_UNKNOWN=1：当前仓库所有 txt 清单都必须 0 行无法识别。
    一旦有人引入 mrs 无法表达的规则类型，这条测试会先失败。
    """
    txt_dir = ROOT / 'txt'
    files = sorted(txt_dir.glob('*.txt'))
    assert files, 'txt/ 下没有清单文件'
    env = dict(os.environ)
    env.setdefault('PYTHONIOENCODING', 'utf-8')
    for f in files:
        r = subprocess.run(
            [sys.executable, str(SCRIPT_DIR / 'classify-rules.py'), str(f),
             str(tmp_path / 'ip.txt'), str(tmp_path / 'dom.txt'),
             '--config', str(ROOT / 'config.yaml')],
            cwd=str(ROOT), env=env, capture_output=True,
        )
        assert r.returncode == 0, f'{f.name}: {r.stderr.decode("utf-8", "replace")}'
        ip_n, dom_n, unknown_n = _parse_counts(r)
        assert unknown_n == 0, f'{f.name} 出现 {unknown_n} 行无法识别：' \
                               f'{r.stderr.decode("utf-8", "replace")}'
        assert ip_n + dom_n > 0, f'{f.name} 清洗后 0 条有效规则'


def test_readme_and_config_are_in_sync():
    """文档/配置漂移守护：新增关键选项必须在 README 与 config.yaml 同步出现。"""
    readme = (ROOT / 'README.md').read_text(encoding='utf-8')
    config = (ROOT / 'config.yaml').read_text(encoding='utf-8')
    for token in ['bare_domain', '--prune', '--naming', 'STRICT_UNKNOWN',
                  'requirements-dev.txt', 'pytest', 'Mihomo Domain Wildcards']:
        assert token in readme, f'README.md 缺少 {token}'
    assert 'bare_domain:' in config
    assert 'suffix' in config and 'exact' in config


def test_gitignore_no_dead_rules():
    """.gitignore 不再保留已废弃的临时文件 glob（构建改落 mktemp -d）。"""
    gi = (ROOT / '.gitignore').read_text(encoding='utf-8')
    for dead in ['*_temp.txt', '*_Mihomo.txt', '*_ip.txt', '*_domain.txt', 'version.txt']:
        assert dead not in gi, f'.gitignore 仍有死规则 {dead}'
    assert '*.tmp' in gi
    assert '.pytest_cache/' in gi
