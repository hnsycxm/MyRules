# -*- coding: utf-8 -*-
"""共用夹具：按路径加载 script/ 下的两个脚本（文件名含连字符，无法直接 import）。"""
import importlib.util
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SCRIPT_DIR = ROOT / 'script'


def _load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    if spec is None or spec.loader is None:
        raise ImportError(f'无法加载 {path}')
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope='session')
def sort_clash():
    """sort-clash.py 模块。"""
    return _load_module('sort_clash_under_test', SCRIPT_DIR / 'sort-clash.py')


@pytest.fixture(scope='session')
def classify():
    """classify-rules.py 模块（它自己会按相对路径加载 sort-clash.py）。"""
    return _load_module('classify_under_test', SCRIPT_DIR / 'classify-rules.py')


@pytest.fixture
def run_script():
    """返回一个函数：子进程运行 script/ 下的 Python 脚本并返回 CompletedProcess。"""
    import os
    import subprocess

    def _run(script_name, args, env=None, cwd=ROOT):
        merged = dict(os.environ)
        merged.setdefault('PYTHONIOENCODING', 'utf-8')
        if env:
            merged.update(env)
        cmd = [sys.executable, str(SCRIPT_DIR / script_name)] + [str(a) for a in args]
        return subprocess.run(cmd, cwd=str(cwd), env=merged, capture_output=True)

    return _run
