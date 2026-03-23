# MyRules 本地开发指南

## 环境要求

- Python 3.7+
- Bash (Linux/macOS 或 Git Bash for Windows)
- pip

## 快速开始

### 1. 安装依赖

```bash
pip install -r requirements.txt
```

### 2. 准备规则文件

在 `txt` 目录下创建域名列表文件，每行一个域名：

```txt
example.com
google.com
github.com
```

### 3. 运行构建脚本

```bash
bash script/build-combined-rules.sh
```

### 4. 查看生成的文件

```bash
ls *.mrs
```

## 手动测试单个脚本

### 测试域名排序和去重

```bash
python script/sort-clash.py txt/oktv.txt
```

## 常见问题

### Q: Python 版本过低

确保安装 Python 3.7 或更高版本：

```bash
python --version
```

### Q: 找不到 bash

**Windows 用户：** 需要安装 [Git Bash](https://git-scm.com/)

**Linux/macOS：** bash 已预装

### Q: PyYAML 安装失败

尝试使用国内镜像：

```bash
pip install -i https://pypi.tuna.tsinghua.edu.cn/simple pyyaml
```

## 清理缓存

```bash
# 删除临时文件
rm -f *_domain.txt *_Mihomo.txt version.txt mihomo-*

# 删除生成的规则文件
rm -f *.mrs

# 删除 Python 缓存
find . -type d -name "__pycache__" -exec rm -rf {} +
```

## 许可证

MIT License
