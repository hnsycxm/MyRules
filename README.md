# MyRules

将文本域名/IP 清单自动编译为 [Mihomo](https://github.com/MetaCubeX/mihomo)（Clash Meta）二进制规则集（`.mrs`）的自动化仓库。

**本项目仅部署于 GitHub Actions**：`txt/` 是规则源，`mrs/` 是构建产物，CI 每日自动重建并提交。

## 工作原理

```
txt/*.txt ──► 逐行分类（IP / 域名）──► 域名清洗（去重·排序·子域归并）──► mihomo convert-ruleset ──► mrs/*.mrs
```

- **逐行分类**：每一行独立判断是 IP 还是域名，因此同一个文件里混排 IP 与域名也不会丢数据
- **IP 规则**：支持 IPv4 / IPv6 与 CIDR（`1.2.3.4`、`1.2.3.0/24`、`2001:db8::1`、`2001:db8::/32`），单地址会自动补 `/32`、`/128`，编译为 `ipcidr` 规则集
- **域名规则**：去重、排序、子域归并后加 `+.` 前缀，编译为 `domain` 规则集
- 单个文件若清洗后 0 条有效规则，构建会**直接失败**（不再静默跳过），便于及早发现清单错误
- CI 每日北京时间 08:00 自动运行；推送 `txt/**` 变更或手动触发也会重建

### 混合清单的处理

`ipcidr` 与 `domain` 是两种不同的规则集格式，无法塞进同一个文件。因此当某个 `txt` 文件同时包含 IP 与域名时：

| 产物 | 内容 |
| --- | --- |
| `mrs/<名字>.mrs` | IP 部分（ipcidr 规则集） |
| `mrs/<名字>_domain.mrs` | 域名部分（domain 规则集） |

纯域名文件与纯 IP 文件仍沿用原来的单产物命名，不受影响。

## 使用

1. 将本仓库推送到 GitHub（默认分支 `main`）
2. 首次推送后，在 Actions 页手动运行一次 `Auto Update Rules`（或等每日定时任务）
3. 构建完成后，`mrs/*.mrs` 即为可直接引用的订阅规则集

## 本地开发（可选）

需要环境：Python 3.7+、Bash、已安装并加入 PATH 的 `mihomo`。

```bash
pip install -r requirements.txt

# 只清洗域名（对 txt 副本操作，勿直接改源文件）
cp txt/cn.txt /tmp/cn_test.txt
python script/sort-clash.py /tmp/cn_test.txt --config config.yaml

# 只做 IP / 域名分类，结果写入两个临时文件
python script/classify-rules.py /tmp/cn_test.txt /tmp/cn_ip.txt /tmp/cn_domain.txt
# 输出三行：IP 条目数、域名条目数、无法识别的行数
```

> 注意：CI 会自动安装最新版 mihomo；本地运行请自行安装。
> 缺少 PyYAML 时脚本仍可运行，但会回退到默认配置并打印警告。

## 目录结构

```
├── txt/            # 规则源（每行一个域名 / IP）
├── mrs/            # 构建产物（.mrs 二进制规则集）
├── script/
│   ├── build-combined-rules.sh   # 主构建脚本
│   ├── classify-rules.py         # 逐行分类（IP / 域名）
│   └── sort-clash.py             # 域名清洗（去重/排序/子域归并）
├── config.yaml     # 构建配置
└── .github/workflows/auto-update.yml  # CI 工作流
```

## 配置说明

`config.yaml` 中 `rules` 下各项的作用：

| 配置项 | 默认 | 说明 |
| --- | --- | --- |
| `remove_subdomains` | `true` | 子域归并，只保留父域。公共后缀（如 `co.jp`）不会被当作父域，避免误删真实域名 |
| `validate_domains` | `true` | 校验域名格式，非法行会被跳过并在日志中列出 |
| `sort_domains` | `true` | 按字典序输出域名 |
| `parallel_processes` | `4` | 并行处理的文件数；非法值会回退为 `4` 并告警 |

## 清理本地临时文件

```bash
rm -f *_temp.txt *_Mihomo.txt *_ip.txt *_domain.txt version.txt
find . -type d -name "__pycache__" -exec rm -rf {} +
```

## 许可证

MIT License，见 [LICENSE](LICENSE)。
