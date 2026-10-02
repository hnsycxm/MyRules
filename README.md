# MyRules

将文本域名/IP 清单自动编译为 [Mihomo](https://github.com/MetaCubeX/mihomo)（Clash Meta）二进制规则集（`.mrs`）的自动化仓库。

**本项目仅部署于 GitHub Actions**：`txt/` 是规则源，`mrs/` 是构建产物，CI 每日自动重建并提交。

## 工作原理

```
txt/*.txt ──► 类型判定（纯 IP / 域名）──► 清洗（去重·排序·子域归并）──► mihomo convert-ruleset ──► mrs/*.mrs
```

- 纯 IP 文件：自动补 `/32` 掩码后编译为 IP 规则集
- 域名文件：去重、排序、子域归并后编译为域名规则集
- CI 每日北京时间 08:00 自动运行；推送 `txt/**` 变更或手动触发也会重建

## 使用

1. 将本仓库推送到 GitHub（默认分支 `main`）
2. 首次推送后，在 Actions 页手动运行一次 `Auto Update Rules`（或等每日定时任务）
3. 构建完成后，`mrs/*.mrs` 即为可直接引用的订阅规则集

## 本地开发（可选）

需要环境：Python 3.7+、Bash、已安装并加入 PATH 的 `mihomo`。

```bash
pip install -r requirements.txt

# 手动测试单个脚本（对 txt 副本操作，勿直接改源文件）
cp txt/cn.txt /tmp/cn_test.txt
python script/sort-clash.py /tmp/cn_test.txt --config config.yaml
```

> 注意：CI 会自动安装最新版 mihomo；本地运行请自行安装。

## 目录结构

```
├── txt/            # 规则源（每行一个域名 / IP）
├── mrs/            # 构建产物（.mrs 二进制规则集）
├── script/
│   ├── build-combined-rules.sh   # 主构建脚本
│   └── sort-clash.py             # 域名清洗（去重/排序/子域归并）
├── config.yaml     # 构建配置
└── .github/workflows/auto-update.yml  # CI 工作流
```

## 清理本地临时文件

```bash
rm -f *_temp.txt *_Mihomo.txt version.txt
find . -type d -name "__pycache__" -exec rm -rf {} +
```

## 许可证

MIT License，见 [LICENSE](LICENSE)。
