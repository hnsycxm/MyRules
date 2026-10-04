#!/bin/bash
# MyRules 构建脚本
# 逐行分类文本清单，分别编译为 Mihomo（Clash Meta）二进制规则集，保存至 mrs/ 目录
#
# 与旧版的区别：
#   1. 逐行分类（script/classify-rules.py），不再给整个文件打一个标签；
#   2. 支持 IPv6 与 CIDR（标准库 ipaddress），不再只认识 IPv4；
#   3. 不再用 2>/dev/null 掩盖 Python 报错；
#   4. parallel_processes 会做合法性校验；
#   5. 单个文件产出 0 条规则时直接失败，避免 CI 静默通过；
#   6. 纯 IP 与纯域名仍沿用原来的文件名，混合清单才额外产出 *_domain.mrs。

set -euo pipefail

# 切换到脚本所在目录
cd "$(cd "$(dirname "$0")" && pwd)" || exit 1
PROJECT_ROOT="$(pwd)/.."
CONFIG_FILE="$PROJECT_ROOT/config.yaml"
MRS_DIR="$PROJECT_ROOT/mrs"
CLASSIFIER="$PROJECT_ROOT/script/classify-rules.py"
SORT_SCRIPT="$PROJECT_ROOT/script/sort-clash.py"
TASK_DIR=""

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"
}

warn() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $*" >&2
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >&2
}

cleanup() {
    log "检测到退出，正在清理临时文件..."
    rm -f ./*_temp.txt ./*_Mihomo.txt ./*_ip.txt ./*_domain.txt version.txt
    [ -n "$TASK_DIR" ] && rm -rf "$TASK_DIR" 2>/dev/null || true
    return 0
}

trap cleanup EXIT INT TERM

# 检查 Python 环境
PYTHON_CMD=""
check_python() {
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &> /dev/null; then
        PYTHON_CMD="python"
    else
        error "未找到 Python，请先安装 Python 3.7+"
        exit 1
    fi
}

# 读取并行度配置，并校验它确实是一个正整数
PARALLEL_PROCESSES=4
load_config() {
    local configured=""
    if [ -f "$CONFIG_FILE" ]; then
        # 这里刻意不加 2>/dev/null：YAML 解析失败需要让调用者看见
        configured=$($PYTHON_CMD -c "
import sys
import yaml
try:
    with open('$CONFIG_FILE', 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f) or {}
except Exception as exc:
    print('读取配置文件失败: %s' % exc, file=sys.stderr)
    sys.exit(1)
rules = config.get('rules') or {}
print(rules.get('parallel_processes', 4))
")
    else
        warn "配置文件不存在：$CONFIG_FILE，使用默认并行度"
    fi

    if [[ "$configured" =~ ^[1-9][0-9]*$ ]]; then
        PARALLEL_PROCESSES="$configured"
    else
        warn "parallel_processes 配置无效（'$configured'），回退为 4"
        PARALLEL_PROCESSES=4
    fi

    # 避免误写成很大的数字把 CI runner 压垮
    if [ "$PARALLEL_PROCESSES" -gt 32 ]; then
        warn "parallel_processes=$PARALLEL_PROCESSES 过大，收敛为 32"
        PARALLEL_PROCESSES=32
    fi
    log "并行进程数配置：$PARALLEL_PROCESSES"
}

TXT_DIR="$PROJECT_ROOT/txt"
TXT_FILES=""
get_txt_files() {
    if [ ! -d "$TXT_DIR" ]; then
        error "txt 目录不存在：$TXT_DIR"
        exit 1
    fi

    TXT_FILES=$(find "$TXT_DIR" -maxdepth 1 -name "*.txt" -type f 2>/dev/null | sort)

    if [ -z "$TXT_FILES" ]; then
        error "在 txt 目录下没有找到任何 .txt 文件"
        exit 1
    fi
}

# 寻找 Mihomo（本项目仅部署于 GitHub Actions，mihomo 由 CI 工作流负责安装）
MIHOMO_BIN=""
setup_mihomo_tool() {
    if command -v mihomo &> /dev/null; then
        MIHOMO_BIN="mihomo"
        log "检测到 mihomo，将直接使用"
        return 0
    fi

    error "未检测到 mihomo。本项目仅部署于 GitHub Actions（CI 会自动安装 mihomo）；如需本地运行，请先自行安装 mihomo 并加入 PATH。"
    exit 1
}

# 用 mihomo 编译一个规则集
compile_ruleset() {
    local kind=$1
    local source_txt=$2
    local target_mrs=$3

    "$MIHOMO_BIN" convert-ruleset "$kind" text "$source_txt" "$target_mrs"
}

# 核心：逐行分类并编译单个规则集
process_rules() {
    local name=$1
    local txt_file=$2
    local ip_txt="${name}_ip.txt"
    local domain_txt="${name}_domain.txt"
    local mihomo_txt="${name}_Mihomo.txt"
    local target_mrs="$MRS_DIR/${name}.mrs"
    local domain_mrs="$MRS_DIR/${name}_domain.mrs"

    log "开始处理规则: $name"

    if [ ! -f "$txt_file" ]; then
        error "输入文件不存在: $txt_file"
        return 1
    fi

    # 逐行分类：IP 与域名分别落盘，混合文件不会丢数据
    local counts ip_count domain_count unknown_count
    if ! counts=$($PYTHON_CMD "$CLASSIFIER" "$txt_file" "$ip_txt" "$domain_txt"); then
        error "规则分类失败：$txt_file"
        return 1
    fi
    ip_count=$(printf '%s\n' "$counts" | sed -n '1p')
    domain_count=$(printf '%s\n' "$counts" | sed -n '2p')
    unknown_count=$(printf '%s\n' "$counts" | sed -n '3p')
    : "${ip_count:=0}" "${domain_count:=0}" "${unknown_count:=0}"

    log "  IP 条目：$ip_count；域名条目：$domain_count；无法识别：$unknown_count"
    if [ "$unknown_count" -gt 0 ]; then
        warn "$name：有 $unknown_count 行既不是 IP 也不是域名，已忽略"
    fi

    if [ "$ip_count" -eq 0 ] && [ "$domain_count" -eq 0 ]; then
        error "$name：清洗后没有任何有效规则，拒绝生成空的 .mrs"
        return 1
    fi

    # 域名条目先清洗（去重/子域归并/排序），IP 条目已在分类阶段规范化
    if [ "$domain_count" -gt 0 ]; then
        cp "$domain_txt" "${name}_temp.txt"
        if ! $PYTHON_CMD "$SORT_SCRIPT" "${name}_temp.txt" --config "$CONFIG_FILE"; then
            error "Python 脚本执行失败：sort-clash.py ($name)"
            return 1
        fi
        if [ ! -s "${name}_temp.txt" ]; then
            if [ "$ip_count" -gt 0 ]; then
                warn "$name：域名部分清洗后为空，只生成 IP 规则集"
                domain_count=0
            else
                error "$name：域名清洗后为空，拒绝生成空的 .mrs"
                return 1
            fi
        fi
    fi

    if [ "$ip_count" -gt 0 ] && [ "$domain_count" -gt 0 ]; then
        # 混合清单：同一份清单不能塞进一个 mrs（ipcidr 与 domain 是两种格式），
        # 因此主产物沿用原名，域名部分另外产出一个 *_domain.mrs
        log "  $name 为混合清单：域名部分将额外编译为 ${name}_domain.mrs"
    fi

    local failed=0

    # 1) 有 IP 就产出 IP 规则集
    if [ "$ip_count" -gt 0 ]; then
        if compile_ruleset ipcidr "$ip_txt" "$target_mrs"; then
            log "✅ 已生成 IP 规则集：$target_mrs（$ip_count 条）"
        else
            error "生成 IP 规则集失败：$target_mrs"
            failed=1
        fi
    fi

    # 2) 有域名就产出域名规则集
    if [ "$domain_count" -gt 0 ]; then
        local domain_target="$target_mrs"
        if [ "$ip_count" -gt 0 ]; then
            domain_target="$domain_mrs"
        fi
        sed "s/^/\\+\\./g" "${name}_temp.txt" > "$mihomo_txt"
        if compile_ruleset domain "$mihomo_txt" "$domain_target"; then
            log "✅ 已生成域名规则集：$domain_target（$domain_count 条）"
        else
            error "生成域名规则集失败：$domain_target"
            failed=1
        fi
    fi

    return "$failed"
}

export -f process_rules compile_ruleset log warn error
# 并行 worker 需要的变量必须显式导出（xargs 会在子 shell 中调用 process_rules）
export PYTHON_CMD PROJECT_ROOT MRS_DIR MIHOMO_BIN CONFIG_FILE
export CLASSIFIER SORT_SCRIPT TASK_DIR PARALLEL_PROCESSES

# 处理全部任务；PARALLEL_PROCESSES > 1 时用 xargs 并行，否则串行。
# 两种模式下子任务失败都会返回非 0，从而让 CI 变红。
run_tasks() {
    local status=0
    if [ "$PARALLEL_PROCESSES" -gt 1 ] && command -v xargs &> /dev/null; then
        log "使用 xargs 并行处理（-$PARALLEL_PROCESSES）"
        status=0
        find "$TASK_DIR" -name 'task_*.txt' -print0 |
            xargs -0 -P "$PARALLEL_PROCESSES" -I {} bash -c '
                task_file="$1"
                IFS="|" read -r name txt_file < "$task_file"
                if process_rules "$name" "$txt_file"; then
                    exit 0
                fi
                echo "$task_file" >> "$TASK_DIR/failed.txt"
                exit 1
            ' _ {} ||
            status=1
    else
        log "串行处理（并行度 $PARALLEL_PROCESSES）"
        local task_file name txt_file
        for task_file in "$TASK_DIR"/task_*.txt; do
            IFS="|" read -r name txt_file < "$task_file"
            process_rules "$name" "$txt_file" || status=1
        done
    fi

    # xargs 在 -P 模式下可能只回传聚合状态，这里再核对一次失败清单
    if [ "$status" -eq 0 ] && [ -f "$TASK_DIR/failed.txt" ]; then
        status=1
    fi
    return "$status"
}

main() {
    log "========================================"
    log "MyRules 构建开始"
    log "========================================"

    check_python
    load_config
    get_txt_files
    setup_mihomo_tool

    if [ ! -f "$CLASSIFIER" ]; then
        error "缺少规则分类脚本：$CLASSIFIER"
        exit 1
    fi
    if [ ! -f "$SORT_SCRIPT" ]; then
        error "缺少域名清洗脚本：$SORT_SCRIPT"
        exit 1
    fi

    # 确保根目录下 mrs 文件夹存在
    mkdir -p "$MRS_DIR"

    TASK_DIR=$(mktemp -d)
    export TASK_DIR

    local txt_file filename name
    for txt_file in $TXT_FILES; do
        filename=$(basename "$txt_file")
        name="${filename%.*}"
        printf '%s|%s\n' "$name" "$txt_file" > "$TASK_DIR/task_${name}.txt"
    done

    local file_count
    file_count=$(find "$TASK_DIR" -name 'task_*.txt' | wc -l | tr -d ' ')
    log "共 $file_count 个规则文件待处理"

    if ! run_tasks; then
        error "构建失败：至少有一个规则文件处理出错，详见上方日志"
        exit 1
    fi

    log "========================================"
    log "✅ 所有规则处理完成！"
    log "========================================"
}

main "$@"
