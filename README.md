# MyRules

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub Actions](https://github.com/yourusername/MyRules/workflows/Auto%20Update%20Rules/badge.svg)](https://github.com/yourusername/MyRules/actions)

## 概述

MyRules 是一个自动化域名规则处理系统，用于将用户自定义的域名列表转换为 Mihomo（Clash Meta）格式的规则文件。项目通过 GitHub Actions 实现完全自动化的构建和更新流程。

## 特性

- ✅ **完全自动化**：GitHub Actions 自动构建和更新
- ✅ **灵活配置**：支持 YAML 配置文件自定义处理选项
- ✅ **批量处理**：并行处理多个规则文件
- ✅ **智能优化**：自动去重、排序、子域名优化
- ✅ **跨平台**：支持 Linux、macOS、Windows
- ✅ **版本管理**：自动记录规则文件版本信息
- ✅ **严格验证**：域名格式验证确保规则质量

## 项目结构

```
MyRules/
├── .github/workflows/
│   └── auto-update.yml          # GitHub Actions 自动化工作流
├── script/
│   ├── build-combined-rules.sh  # 主构建脚本
│   ├── sort-clash.py            # 域名处理和去重脚本
│   ├── config-parser.py         # 配置文件解析器
│   └── version-manager.py       # 版本管理器
├── txt/                         # 用户输入的域名规则文件
│   └── *.txt
├── config.yaml                  # 项目配置文件
├── README.md                    # 项目文档
├── CONTRIBUTING.md              # 贡献指南
└── CHANGELOG.md                 # 更新日志
```

## 快速开始

### 前置要求

- Git
- Bash (Linux/macOS) 或 Git Bash (Windows)
- Python 3.7+
- pip

### 本地使用

1. **克隆仓库**
   ```bash
   git clone https://github.com/yourusername/MyRules.git
   cd MyRules
   ```

2. **安装依赖**
   ```bash
   pip install pyyaml
   ```

3. **准备规则文件**
   在 `txt` 目录下创建 `.txt` 文件，每行一个域名：
   ```
   example.com
   google.com
   github.com
   ```

4. **运行构建脚本**
   ```bash
   bash script/build-combined-rules.sh
   ```

5. **获取结果**
   生成的 `.mrs` 文件将出现在项目根目录

### GitHub Actions 自动化

1. Fork 本仓库到你的 GitHub 账户
2. 在 `txt` 目录添加或修改规则文件
3. 提交并推送到你的仓库
4. GitHub Actions 将自动构建并更新 `.mrs` 文件

## 配置说明

编辑 `config.yaml` 文件来自定义项目行为：

```yaml
# 全局设置
global:
  timezone: "Asia/Shanghai"
  log_level: "info"

# 规则处理设置
rules:
  remove_subdomains: true      # 是否移除子域名
  validate_domains: true       # 是否验证域名格式
  sort_domains: true           # 是否排序域名
  parallel_processes: 4        # 并发处理数

# Mihomo 工具设置
mihomo:
  download_source: "github"    # 下载源
  version_channel: "Prerelease-Alpha"
  timeout: 300

# 输出设置
output:
  keep_temp_files: false       # 是否保留临时文件
  add_version_info: true       # 是否添加版本信息
  formats: ["mrs"]             # 输出格式
```

## 工作流程

### 自动化触发

- **推送触发**：`txt/` 目录文件变更时自动运行
- **定时触发**：每天北京时间上午 8:00
- **手动触发**：在 GitHub Actions 页面手动运行

### 处理流程

1. **初始化**：加载配置，下载 Mihomo 工具
2. **文件发现**：扫描 `txt/` 目录所有 `.txt` 文件
3. **批量处理**：并行处理每个文件
   - 域名提取和验证
   - 去重和排序
   - 子域名优化
   - 转换为 Mihomo 格式
4. **版本记录**：生成版本信息
5. **自动提交**：提交变更到仓库

## 技术细节

### 域名格式支持

支持的输入格式：
- `domain.com` - 标准域名
- `+.domain.com` - Mihomo 格式域名
- `DOMAIN-SUFFIX,domain.com` - Clash 规则格式

### 处理逻辑

1. **域名提取**：从多种格式中提取有效域名
2. **格式验证**：严格验证域名格式
   - 最大长度 253 字符
   - 标签最大长度 63 字符
   - 正则表达式匹配
3. **去重优化**：移除重复域名和子域名
4. **排序**：按字母顺序排列
5. **格式转换**：转换为 Mihomo `.mrs` 二进制格式

### 性能优化

- **异步处理**：使用 Python asyncio 处理大文件
- **并行处理**：Bash 并行处理多个规则文件
- **分块读取**：每次读取 10KB 减少内存占用
- **智能去重**：使用集合数据结构快速去重

## 使用场景

- **个人代理规则管理**：自定义域名分流规则
- **网络防火墙**：域名黑名单/白名单
- **广告拦截**：构建自定义广告域名列表
- **企业网络管理**：集中管理域名访问规则
- **开发者工具**：自动化规则文件生成

## 贡献指南

欢迎贡献代码、报告问题或提出建议！

请查看 [CONTRIBUTING.md](CONTRIBUTING.md) 了解详细信息。

## 更新日志

查看 [CHANGELOG.md](CHANGELOG.md) 了解版本更新历史。

## 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 致谢

- [Mihomo](https://github.com/MetaCubeX/mihomo) - 强大的代理核心
- [Clash](https://github.com/Dreamacro/clash) - 原始项目灵感来源

## 联系方式

- 提交 Issue：[GitHub Issues](https://github.com/yourusername/MyRules/issues)
- 讨论：[GitHub Discussions](https://github.com/yourusername/MyRules/discussions)

---

**注意**：本项目仅供学习和个人使用，请遵守当地法律法规。
