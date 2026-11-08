#!/usr/bin/env bash
# MyRules 构建脚本（优化版）
# 逐行分类文本清单，分别编译为 Mihomo（Clash Meta）二进制规则集，保存至 mrs/ 目录
#
# 约定：
#   - 纯 IP / 纯域名清单：产出 mrs/<name>.mrs
#   - 混合清单：IP 部分为 mrs/<name>.mrs，域名部分为 mrs/<name>_domain.mrs
#   - 每个清单先在独立临时目录中完整构建，全部成功后才写入 mrs/（全有或全无）
#
# 可选环境变量：
#   MIHOMO_BIN=/path/to/mihomo   指定 mihomo 可执行文件
#   STRICT_UNKNOWN=1             存在无法识别的行时视为失败（默认仅告警）
#   NAMING=legacy|strict         命名方案（默认 legacy，等价于 --naming=...）
#                                strict：始终产出 <name>_ip.mrs / <name>_domain.mrs，
#                                避免清单内容变化时 <name>.mrs 在 ipcidr/domain 之间翻转
#
# 参数：
#   --prune          构建全部成功后，删除 mrs/ 中不再对应任何 txt 的 .mrs
#   --naming=MODE    同 NAMING
#   -h, --help       显示帮助

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config.yaml"
TXT_DIR="$PROJECT_ROOT/txt"
MRS_DIR="$PROJECT_ROOT/mrs"
CLASSIFIER="$PROJECT_ROOT/script/classify-rules.py"
SORT_SCRIPT="$PROJECT_ROOT/script/sort-clash.py"

WORK_DIR=""
PYTHON_CMD=""
MIHOMO_BIN="${MIHOMO_BIN:-}"
STRICT_UNKNOWN="${STRICT_UNKNOWN:-0}"
NAMING="${NAMING:-legacy}"
PRUNE=0
PARALLEL_PROCESSES=4
TXT_FILES=()

# Python 全程以 UTF-8 读写文本与输出日志，覆盖 load_config 的内联 python -c、
# classify-rules.py、sort-clash.py 以及 xargs 派生出的子 shell。
# 脚本自身也在入口调用 sort_clash.ensure_utf8_stdio()，两者叠加构成双重兜底：
# 即使有人手动单独运行某个 Python 脚本、没设本变量，也不会在 GBK 等非 UTF-8
# 控制台因打印中文/emoji 抛 UnicodeEncodeError 而误报构建失败。
export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"

# ---------------------------------------------------------------- 日志
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

# TASK_TAG 由 process_rules 以 local 方式设置（bash 动态作用域），用于在并行日志中区分任务
log() { echo "$(timestamp) [INFO] ${TASK_TAG:-}$*"; }

warn() {
    echo "$(timestamp) [WARN] ${TASK_TAG:-}$*" >&2
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then echo "::warning::${TASK_TAG:-}$*"; fi
}

error() {
    echo "$(timestamp) [ERROR] ${TASK_TAG:-}$*" >&2
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then echo "::error::${TASK_TAG:-}$*"; fi
}

# ---------------------------------------------------------------- 退出清理
# 只清理自己创建的临时目录；信号只负责转成正常 exit，由 EXIT trap 统一收尾（只执行一次）
cleanup() {
    local rc=$?
    trap - EXIT
    if [ -n "$WORK_DIR" ]; then rm -rf "$WORK_DIR"; fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---------------------------------------------------------------- 环境检查
check_python() {
    local c
    for c in python3 python; do
        if command -v "$c" > /dev/null 2>&1; then
            PYTHON_CMD="$c"
            break
        fi
    done
    if [ -z "$PYTHON_CMD" ]; then
        error "未找到 Python，请先安装 Python 3.7+"
        exit 1
    fi
    if ! "$PYTHON_CMD" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 7) else 1)'; then
        error "Python 版本过低，需要 3.7+"
        exit 1
    fi
}

load_config() {
    local configured=""
    if [ -f "$CONFIG_FILE" ]; then
        # 路径通过 argv 传入，避免拼进 Python 源码；报错不吞，直接让调用者看到
        configured=$("$PYTHON_CMD" -c '
import sys
try:
    import yaml
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        config = yaml.safe_load(f) or {}
    rules = config.get("rules") or {}
    print(rules.get("parallel_processes", 4))
except Exception as exc:
    print("读取配置文件失败: %s" % exc, file=sys.stderr)
    sys.exit(1)
' "$CONFIG_FILE") || { error "解析配置文件失败：$CONFIG_FILE"; exit 1; }
    else
        warn "配置文件不存在：$CONFIG_FILE，使用默认并行度"
    fi

    if [[ "$configured" =~ ^[1-9][0-9]*$ ]]; then
        PARALLEL_PROCESSES="$configured"
    else
        if [ -n "$configured" ]; then warn "parallel_processes 配置无效（'$configured'），回退为 4"; fi
        PARALLEL_PROCESSES=4
    fi

    if [ "$PARALLEL_PROCESSES" -gt 32 ]; then
        warn "parallel_processes=$PARALLEL_PROCESSES 过大，收敛为 32"
        PARALLEL_PROCESSES=32
    fi
}

get_txt_files() {
    if [ ! -d "$TXT_DIR" ]; then
        error "txt 目录不存在：$TXT_DIR"
        exit 1
    fi
    # NUL 分隔 + 数组：文件名含空格也安全；LC_ALL=C 保证排序确定
    local f
    while IFS= read -r -d '' f; do
        TXT_FILES+=("$f")
    done < <(find "$TXT_DIR" -maxdepth 1 -type f -name '*.txt' -print0 | LC_ALL=C sort -z)

    if [ "${#TXT_FILES[@]}" -eq 0 ]; then
        error "在 txt 目录下没有找到任何 .txt 文件"
        exit 1
    fi
}

setup_mihomo_tool() {
    if [ -n "$MIHOMO_BIN" ] && command -v "$MIHOMO_BIN" > /dev/null 2>&1; then
        :
    elif command -v mihomo > /dev/null 2>&1; then
        MIHOMO_BIN="mihomo"
    else
        error "未检测到 mihomo。本项目仅部署于 GitHub Actions（CI 会自动安装）；本地运行请先安装 mihomo 并加入 PATH，或设置 MIHOMO_BIN。"
        exit 1
    fi
    log "使用 mihomo：$(command -v "$MIHOMO_BIN")"
}

# ---------------------------------------------------------------- 核心处理
compile_ruleset() {
    local kind=$1 source_txt=$2 target_mrs=$3
    "$MIHOMO_BIN" convert-ruleset "$kind" text "$source_txt" "$target_mrs"
}

# 先复制为同目录临时文件再 mv，避免读者看到写了一半的 .mrs
install_mrs() {
    local src=$1 dst=$2
    [ -s "$src" ] || return 1
    cp -f "$src" "$dst.tmp" && mv -f "$dst.tmp" "$dst"
}

# 注意：本函数在 `if ! process_rules` 中被调用，bash 会因此关闭其内部的 set -e，
# 所以下面每一步都必须显式检查返回值。
process_rules() {
    local name=$1 txt_file=$2
    local TASK_TAG="[$name] "
    local work="$WORK_DIR/$name"
    local ip_txt="$work/ip.txt" domain_txt="$work/domain.txt" mihomo_txt="$work/mihomo.txt"
    local stage_ip="$work/ip.mrs" stage_domain="$work/domain.mrs"
    local counts ip_count domain_count unknown_count

    log "开始处理规则"

    if [ ! -f "$txt_file" ]; then
        error "输入文件不存在: $txt_file"
        return 1
    fi
    mkdir -p "$work" || { error "无法创建临时目录：$work"; return 1; }

    # 1) 逐行分类（classify-rules.py 输出三行：IP 数 / 域名数 / 无法识别数）
    if ! counts=$("$PYTHON_CMD" "$CLASSIFIER" "$txt_file" "$ip_txt" "$domain_txt" --config "$CONFIG_FILE"); then
        error "规则分类失败：$txt_file"
        return 1
    fi
    { read -r ip_count || true; read -r domain_count || true; read -r unknown_count || true; } <<< "$counts"
    ip_count=${ip_count:-0}
    domain_count=${domain_count:-0}
    unknown_count=${unknown_count:-0}
    if ! [[ $ip_count =~ ^[0-9]+$ && $domain_count =~ ^[0-9]+$ && $unknown_count =~ ^[0-9]+$ ]]; then
        error "分类脚本输出异常（期望三个整数）：$counts"
        return 1
    fi

    if [ "$unknown_count" -gt 0 ]; then
        if [ "$STRICT_UNKNOWN" = "1" ]; then
            error "有 $unknown_count 行既不是 IP 也不是域名（STRICT_UNKNOWN=1）"
            return 1
        fi
        warn "有 $unknown_count 行既不是 IP 也不是域名，已忽略"
    fi

    # 2) 域名清洗（去重/冗余归并/排序）；之后以清洗后的真实行数为准
    #    分类阶段已把每条规则写成显式的 Mihomo 写法（+.x / .x / *.x / 精确 x），
    #    因此这里必须按 exact 解释，不能再让裸域名二次变成后缀。
    if [ "$domain_count" -gt 0 ]; then
        if ! "$PYTHON_CMD" "$SORT_SCRIPT" "$domain_txt" --config "$CONFIG_FILE" --bare-domain exact; then
            error "sort-clash.py 执行失败"
            return 1
        fi
        domain_count=$(awk 'NF{n++} END{print n+0}' "$domain_txt") || return 1
        if [ "$domain_count" -eq 0 ]; then
            if [ "$ip_count" -gt 0 ]; then
                warn "域名部分清洗后为空，只生成 IP 规则集"
            fi
        fi
    fi
    if [ "$ip_count" -gt 0 ]; then
        ip_count=$(awk 'NF{n++} END{print n+0}' "$ip_txt") || return 1
    fi

    if [ "$ip_count" -eq 0 ] && [ "$domain_count" -eq 0 ]; then
        error "清洗后没有任何有效规则，拒绝生成空的 .mrs"
        return 1
    fi
    log "IP：$ip_count 条；域名：$domain_count 条"

    # 3) 规划产物。legacy 沿用原命名；strict 固定使用 _ip / _domain 后缀
    local -a out_src=() out_dst=()
    if [ "$NAMING" = "strict" ]; then
        if [ "$ip_count" -gt 0 ]; then out_src+=("$stage_ip"); out_dst+=("${name}_ip.mrs"); fi
        if [ "$domain_count" -gt 0 ]; then out_src+=("$stage_domain"); out_dst+=("${name}_domain.mrs"); fi
    elif [ "$ip_count" -gt 0 ] && [ "$domain_count" -gt 0 ]; then
        out_src=("$stage_ip" "$stage_domain")
        out_dst=("${name}.mrs" "${name}_domain.mrs")
        log "混合清单：IP → ${name}.mrs，域名 → ${name}_domain.mrs"
    elif [ "$ip_count" -gt 0 ]; then
        out_src=("$stage_ip"); out_dst=("${name}.mrs")
    else
        out_src=("$stage_domain"); out_dst=("${name}.mrs")
    fi

    # 产物名若恰好是另一份清单的主产物名，则视为命名冲突
    local i base
    for i in "${!out_dst[@]}"; do
        base="${out_dst[$i]%.mrs}"
        if [ "$base" != "$name" ] && [ -e "$TXT_DIR/$base.txt" ]; then
            error "命名冲突：将产出 ${out_dst[$i]}，但 txt/$base.txt 也存在"
            return 1
        fi
    done

    # 4) 编译到临时目录（任何一步失败都不会动 mrs/ 下的现有文件）
    if [ "$ip_count" -gt 0 ]; then
        compile_ruleset ipcidr "$ip_txt" "$stage_ip" || { error "编译 IP 规则集失败"; return 1; }
    fi
    if [ "$domain_count" -gt 0 ]; then
        # 规则已是 Mihomo domain 规则集的写法，必须原样交给 mihomo，不能再加前缀，
        # 否则 *.x（一级子域）、.x（仅子域）、精确匹配的语义都会被改写。
        # 这里只做防御性清理：去 CR、去空行。
        sed -e 's/\r$//' -e '/^[[:space:]]*$/d' "$domain_txt" > "$mihomo_txt" \
            || { error "生成 Mihomo 文本失败"; return 1; }
        compile_ruleset domain "$mihomo_txt" "$stage_domain" || { error "编译域名规则集失败"; return 1; }
    fi

    # 5) 全部成功后再落盘
    for i in "${!out_dst[@]}"; do
        install_mrs "${out_src[$i]}" "$MRS_DIR/${out_dst[$i]}" || { error "写入 ${out_dst[$i]} 失败"; return 1; }
    done

    # 6) 清理该清单旧版本遗留的产物（不碰属于其他清单的文件）
    local cand d keep
    for cand in "$name" "${name}_ip" "${name}_domain"; do
        keep=0
        for d in "${out_dst[@]}"; do
            if [ "$d" = "$cand.mrs" ]; then keep=1; fi
        done
        if [ "$keep" -eq 1 ]; then continue; fi
        if [ "$cand" != "$name" ] && [ -e "$TXT_DIR/$cand.txt" ]; then continue; fi
        rm -f "$MRS_DIR/$cand.mrs"
    done

    # 7) 记录结果，供汇总与 --prune 使用
    printf '%s\n' "${out_dst[@]}" > "$WORK_DIR/result/$name.out" || return 1
    printf '%s\t%s\t%s\t%s\n' "$name" "$ip_count" "$domain_count" "${out_dst[*]}" \
        > "$WORK_DIR/result/$name.sum" || return 1

    log "✅ 完成"
}

# 单个任务入口：失败时留下标记文件，供汇总报告
run_one() {
    local txt_file=$1 filename name
    filename=$(basename "$txt_file")
    name="${filename%.txt}"
    if ! process_rules "$name" "$txt_file"; then
        : > "$WORK_DIR/failed/$name"
        return 1
    fi
}

export -f timestamp log warn error compile_ruleset install_mrs process_rules run_one
export PYTHON_CMD MIHOMO_BIN CONFIG_FILE TXT_DIR MRS_DIR CLASSIFIER SORT_SCRIPT STRICT_UNKNOWN NAMING

# 统一用 xargs 调度；并行度为 1 时即串行。某个任务失败不会中断其余任务。
run_tasks() {
    local total=${#TXT_FILES[@]} workers=$PARALLEL_PROCESSES
    if [ "$workers" -gt "$total" ]; then workers=$total; fi
    log "共 $total 个规则文件，并行度 $workers"

    mkdir -p "$WORK_DIR/failed" "$WORK_DIR/result"
    local xargs_rc=0
    printf '%s\0' "${TXT_FILES[@]}" |
        xargs -0 -n1 -P "$workers" bash -c 'set -u; run_one "$1"' _ || xargs_rc=$?

    local f failed=()
    for f in "$WORK_DIR"/failed/*; do
        [ -e "$f" ] && failed+=("$(basename "$f")")
    done

    if [ "${#failed[@]}" -gt 0 ]; then
        error "以下规则集构建失败：${failed[*]}"
        return 1
    fi
    if [ "$xargs_rc" -ne 0 ]; then
        error "并行调度异常退出（xargs 返回 $xargs_rc）"
        return 1
    fi
}

usage() {
    sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --prune) PRUNE=1 ;;
            --naming=*) NAMING="${1#*=}" ;;
            -h | --help) usage; exit 0 ;;
            *) error "未知参数：$1"; usage >&2; exit 2 ;;
        esac
        shift
    done
    case "$NAMING" in
        legacy | strict) ;;
        *) error "NAMING 只能是 legacy 或 strict，当前：$NAMING"; exit 2 ;;
    esac
}

print_summary() {
    local f name ip dom outs
    local md="${GITHUB_STEP_SUMMARY:-}"
    log "构建汇总："
    printf '  %-24s %8s %8s  %s\n' "清单" "IP" "域名" "产物"
    if [ -n "$md" ]; then
        printf '### MyRules 构建汇总\n\n| 清单 | IP | 域名 | 产物 |\n|---|---:|---:|---|\n' >> "$md"
    fi
    for f in "$WORK_DIR"/result/*.sum; do
        [ -e "$f" ] || continue
        IFS=$'\t' read -r name ip dom outs < "$f"
        printf '  %-24s %8s %8s  %s\n' "$name" "$ip" "$dom" "$outs"
        if [ -n "$md" ]; then printf '| %s | %s | %s | %s |\n' "$name" "$ip" "$dom" "$outs" >> "$md"; fi
    done
}

# 仅在全部任务成功后调用：删除 mrs/ 中不在本次产物清单里的 .mrs
prune_stale() {
    local expected="$WORK_DIR/expected.txt" f base
    cat "$WORK_DIR"/result/*.out | LC_ALL=C sort -u > "$expected"
    for f in "$MRS_DIR"/*.mrs; do
        [ -e "$f" ] || continue
        base=$(basename "$f")
        if ! grep -qxF -- "$base" "$expected"; then
            rm -f "$f"
            log "🧹 已删除过期规则集：$base"
        fi
    done
}

main() {
    parse_args "$@"
    log "========================================"
    log "MyRules 构建开始（命名方案：$NAMING）"
    log "========================================"

    check_python
    load_config
    log "并行进程数配置：$PARALLEL_PROCESSES"
    get_txt_files
    setup_mihomo_tool
    export MIHOMO_BIN

    local f
    for f in "$CLASSIFIER" "$SORT_SCRIPT"; do
        if [ ! -f "$f" ]; then
            error "缺少脚本：$f"
            exit 1
        fi
    done

    mkdir -p "$MRS_DIR"
    WORK_DIR=$(mktemp -d)
    export WORK_DIR

    if ! run_tasks; then
        error "构建失败：详见上方日志"
        exit 1
    fi

    print_summary
    if [ "$PRUNE" -eq 1 ]; then prune_stale; fi

    log "========================================"
    log "✅ 所有规则处理完成！mrs 目录共 $(find "$MRS_DIR" -maxdepth 1 -name '*.mrs' | wc -l | tr -d ' ') 个规则集"
    log "========================================"
}

main "$@"
