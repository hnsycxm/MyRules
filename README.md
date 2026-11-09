# MyRules

将文本域名/IP 清单自动编译为 [Mihomo](https://github.com/MetaCubeX/mihomo)（Clash Meta）二进制规则集（`.mrs`）的自动化仓库。

**本项目仅部署于 GitHub Actions**：`txt/` 是规则源，`mrs/` 是构建产物，CI 每日自动重建并提交。

## 工作原理

```
txt/*.txt
   │
   ├─► 逐行分类并规范化（classify-rules.py）
   │     IP    → CIDR 文本（补 /32、/128，合并重叠/相邻网段）
   │     域名  → 显式 Mihomo domain 写法（+.x / .x / *.x / 精确 x）
   │
   ├─► 域名冗余归并（sort-clash.py，按 Mihomo 通配语义）
   │
   └─► mihomo convert-ruleset（domain / ipcidr）──► mrs/*.mrs
        全部清单都编译成功后才统一落盘（全有或全无）
```

- **一行一判**：每行独立判断是 IP 还是域名，因此同一文件混排 IP 与域名也不会丢数据
- **IP 规则**：支持 IPv4 / IPv6 与 CIDR（`1.2.3.4`、`1.2.3.0/24`、`2001:db8::1`、`2001:db8::/32`），单地址自动补 `/32`、`/128`，并合并重叠/相邻网段，编译为 `ipcidr` 规则集
- **域名规则**：分类阶段就把每条规则写成显式的 Mihomo 写法并原样交给编译器，**不再统一加 `+.` 前缀**；清洗阶段去重、按 Mihomo 通配语义做冗余归并（如 `+.example.com` 覆盖 `example.com`、`*.example.com`），公共后缀（`co.jp` 等）不会被当作可吸收的父域
- **域名写法**（Mihomo Domain Wildcards，语义原样保留）：

  | 写法 | 匹配范围 |
  | --- | --- |
  | `example.com` | 仅 `example.com`（精确） |
  | `*.example.com` | 一级子域，不含 `example.com`、不含 `a.b.example.com` |
  | `.example.com` | 任意级子域，不含 `example.com` |
  | `+.example.com` | `example.com` 及其所有子域（等价 `DOMAIN-SUFFIX`） |
  | `a.*.example.com` | 标签位 `*` 恰好匹配一级 |

  也接受 Clash 规则写法 `DOMAIN,x`（→ 精确）、`DOMAIN-SUFFIX,x`（→ `+.x`）、`IP-CIDR,x[,策略]`。
- **无法识别的行**：`DOMAIN-KEYWORD` / `DOMAIN-REGEX` / `DOMAIN-WILDCARD` / `GEOIP` / `PROCESS-NAME` 等 mrs 无法无损表达的类型不再静默丢弃，会告警并列出明细；设置 `STRICT_UNKNOWN=1` 时视为构建失败
- **单个文件清洗后 0 条有效规则**：构建直接失败（不静默跳过）；某个清单失败不影响其他清单，但整次构建最终以失败退出
- CI 每日北京时间 08:00 自动运行；推送 `txt/**` 变更或手动触发也会重建

### 混合清单的处理

`ipcidr` 与 `domain` 是两种不同的规则集格式，无法塞进同一个文件。因此当某个 `txt` 文件同时包含 IP 与域名时（默认 `legacy` 命名）：

| 产物 | 内容 |
| --- | --- |
| `mrs/<名字>.mrs` | IP 部分（ipcidr 规则集） |
| `mrs/<名字>_domain.mrs` | 域名部分（domain 规则集） |

纯域名文件与纯 IP 文件仍沿用单产物命名 `mrs/<名字>.mrs`，不受影响。

> 注意：`legacy` 下主产物 `mrs/<名字>.mrs` 的类型取决于清单内容，清单从纯域名变混合时会由 `domain` 翻转为 `ipcidr`。如需稳定命名，用 `--naming=strict`（或 `NAMING=strict`）：始终产出 `mrs/<名字>_ip.mrs` 与 `mrs/<名字>_domain.mrs`，各按是否存在对应内容决定。切换命名方案会改变产物文件名，引用方需同步修改。
>
> 本仓库的 `cn.txt`（纯域名）与 `cn_ip.txt`（纯 IP）是人工拆分的两个清单，恰好与 `legacy` 命名吻合；若改用 `strict`，会得到 `cn_domain.mrs` 与 `cn_ip_ip.mrs`。构建脚本会检测"产物名与另一份清单的主产物名冲突"并拒绝构建。

### 构建命令行选项

```bash
./script/build-combined-rules.sh [选项]

  --prune          全部构建成功后，删除 mrs/ 中已不对应任何 txt 的过期 .mrs
  --naming=MODE    legacy（默认）| strict
  -h, --help       显示帮助
```

环境变量：`MIHOMO_BIN`（指定 mihomo 路径）、`STRICT_UNKNOWN=1`（无法识别的行视为失败）、`NAMING`（同 `--naming`）、`PYTHONIOENCODING`（默认设为 `utf-8`）。

CI 默认以 `STRICT_UNKNOWN=1` + `--prune` 运行，保证脏数据会被拦下、删除源清单后旧 `.mrs` 不会残留。

> 一个反直觉但语义正确的行为：默认 `bare_domain: suffix` 下，清单里写裸父域 `example.com` 会被扩成 `+.example.com`，进而把同域所有精确/通配规则都归并掉（例如 7 条子规则 → 1 条）。若想保留精确匹配，把该项设为 `exact`，或显式写 `DOMAIN,example.com`。

## 使用

1. 将本仓库推送到 GitHub（默认分支 `main`）
2. 首次推送后，在 Actions 页手动运行一次 `Auto Update Rules`（或等每日定时任务）
3. 构建完成后，`mrs/*.mrs` 即为可直接引用的订阅规则集

## 本地开发（可选）

需要环境：Python 3.7+、Bash、已安装并加入 PATH 的 `mihomo`。

```bash
pip install -r requirements.txt

# 完整构建（需要 mihomo；临时文件自动落在系统临时目录，无需手工清理）
./script/build-combined-rules.sh
./script/build-combined-rules.sh --prune --naming=legacy

# 只做 IP / 域名分类，结果写入两个临时文件
python script/classify-rules.py txt/cn.txt /tmp/cn_ip.txt /tmp/cn_domain.txt
# stdout 严格三行：IP 条目数、域名条目数、无法识别的行数；告警一律走 stderr

# 只清洗域名（原地改写文件，务必对副本操作，勿直接改源文件）
cp txt/cn.txt /tmp/cn_test.txt
python script/sort-clash.py /tmp/cn_test.txt --config config.yaml
# 输入已是 classify-rules.py 产出的显式写法时，必须加 --bare-domain exact
```

> 注意：CI 会自动安装最新版 mihomo；本地运行请自行安装，或设置 `MIHOMO_BIN=/path/to/mihomo`。
> 缺少 PyYAML 时脚本仍可运行，但会回退到默认配置并打印警告。
> Python 全程以 UTF-8 输出（脚本入口与 `PYTHONIOENCODING` 双重兜底），在非 UTF-8 终端下日志可能是乱码，但不会崩溃或误报失败。

## 目录结构

```
├── txt/            # 规则源（每行一个域名 / IP / Clash 规则）
├── mrs/            # 构建产物（.mrs 二进制规则集）
├── script/
│   ├── build-combined-rules.sh   # 主构建脚本（分类 → 归并 → 编译 → 落盘）
│   ├── classify-rules.py         # 逐行分类并规范化成显式 Mihomo 写法
│   └── sort-clash.py             # 域名清洗（去重 / 排序 / 按通配语义冗余归并）
├── config.yaml     # 构建配置
├── requirements.txt      # 运行依赖（PyYAML）
├── .github/workflows/
│   └── auto-update.yml   # 每日 / 推送时重建并提交 mrs
└── README.md
```

## 配置说明

`config.yaml` 中 `rules` 下各项的作用：

| 配置项 | 默认 | 说明 |
| --- | --- | --- |
| `remove_subdomains` | `true` | 按 Mihomo 通配语义做冗余归并（如 `+.example.com` 覆盖 `example.com`）。公共后缀（如 `co.jp`）不会被当作可吸收的父域 |
| `validate_domains` | `true` | 校验域名格式，非法行会被跳过并在日志中列出 |
| `sort_domains` | `true` | 按主机排序输出域名 |
| `bare_domain` | `suffix` | 裸域名解释方式：`suffix` → `+.example.com`（匹配自身及所有子域，历史默认）；`exact` → 仅匹配自身。显式写法（`+.x` / `.x` / `*.x` / `DOMAIN,x` / `DOMAIN-SUFFIX,x`）不受影响 |
| `parallel_processes` | `4` | 并行处理的文件数（1~32）；非法值回退为 `4` 并告警 |

## 清理本地临时文件

构建脚本的临时文件统一落在系统临时目录（`mktemp -d`），退出时由 `trap` 自动清理，仓库内不再产生 `_temp.txt` / `_Mihomo.txt` 等文件。日常只需按需清理 Python 缓存：

```bash
find . -type d -name "__pycache__" -exec rm -rf {} +
```

## 许可证

MIT License，见 [LICENSE](LICENSE)。
