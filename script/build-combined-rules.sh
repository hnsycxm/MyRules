#!/bin/bash
# MyRules 构建脚本
# 用于批量处理域名/IP规则并生成 Mihomo 格式文件至 mrs 目录

set -e  # 遇到错误立即退出

# 切换到脚本所在目录
cd "$(cd "$(dirname "$0")" && pwd)" || exit 1
PROJECT_ROOT="$(pwd)/.."
CONFIG_FILE="$PROJECT_ROOT/config.yaml"
MRS_DIR="$PROJECT_ROOT/mrs"
TASK_DIR=""

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >&2
}

cleanup() {
    log "检测到退出，正在清理临时文件..."
    rm -f ./*_domain.txt ./*_ip.txt ./*_Mihomo.txt version.txt
    [ -n "$TASK_DIR" ] && rm -rf "$TASK_DIR" 2>/dev/null || true
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

PARALLEL_PROCESSES=4
load_config() {
    if [ -f "$CONFIG_FILE" ] && [ -n "$PYTHON_CMD" ]; then
        PARALLEL_PROCESSES=$($PYTHON_CMD -c "
import yaml
try:
    with open('$CONFIG_FILE', 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    print(config.get('rules', {}).get('parallel_processes', 4))
except:
    print(4)
" 2>/dev/null || echo 4)
    fi
    log "并行进程数配置：$PARALLEL_PROCESSES"
}

TXT_DIR="$PROJECT_ROOT/txt"
get_txt_files() {
    if [ ! -d "$TXT_DIR" ]; then
        error "txt 目录不存在：$TXT_DIR"
        exit 1
    fi

    TXT_FILES=$(find "$TXT_DIR" -maxdepth 1 -name "*.txt" -type f 2>/dev/null)

    if [ -z "$TXT_FILES" ]; then
        error "在 txt 目录下没有找到任何 .txt 文件"
        exit 1
    fi
}

# 寻找或安装 Mihomo
MIHOMO_BIN=""
setup_mihomo_tool() {
    if command -v mihomo &> /dev/null; then
        MIHOMO_BIN="mihomo"
        log "检测到全局 Mihomo 命令，将直接使用"
        return 0
    fi

    log "未检测到全局 Mihomo，开始下载预编译版本..."
    local platform mihomo_os
    platform="$(uname -s)"
    case "$platform" in
        Linux*)   mihomo_os="linux" ;;
        Darwin*)  mihomo_os="darwin" ;;
        CYGWIN*|MINGW*|MSYS*) mihomo_os="windows" ;;
        *)        mihomo_os="linux" ;;
    esac

    local cache_dir="$PROJECT_ROOT/.cache"
    mkdir -p "$cache_dir"

    local version_file="$cache_dir/version.txt"
    curl -s -L -o "$version_file" https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/version.txt || wget -q -O "$version_file" https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/version.txt

    local version
    version=$(cat "$version_file")

    local tool_name
    if [ "$mihomo_os" = "windows" ]; then
        tool_name="mihomo-windows-amd64-$version.exe"
    else
        tool_name="mihomo-$mihomo_os-amd64-$version"
    fi

    if [ ! -f "$cache_dir/$tool_name" ]; then
        local download_url="https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/$tool_name.gz"
        curl -s -L -o "$cache_dir/$tool_name.gz" "$download_url" || wget -q -O "$cache_dir/$tool_name.gz" "$download_url"
        gzip -d "$cache_dir/$tool_name.gz"
        chmod +x "$cache_dir/$tool_name"
    fi

    MIHOMO_BIN="$cache_dir/$tool_name"
    log "已加载 Mihomo 可执行文件: $MIHOMO_BIN"
}

# 核心：处理规则并转换为二进制文件保存至 /mrs 目录
process_rules() {
    local name=$1
    local txt_file=$2
    local domain_temp="${name}_domain.txt"
    local mihomo_txt_file="${name}_Mihomo.txt"
    local target_mrs_file="$MRS_DIR/${name}.mrs"

    log "开始处理规则: $name"

    if [ ! -f "$txt_file" ]; then
        error "输入文件不存在: $txt_file"
        return 1
    fi

    cp "$txt_file" "$domain_temp"
    sed -i 's/\r//' "$domain_temp" 2>/dev/null || true

    # 调用 Python 脚本对域名清洗、过滤子域名并排序
    $PYTHON_CMD "$PROJECT_ROOT/script/sort-clash.py" "$domain_temp" --config "$CONFIG_FILE" || {
        error "Python 脚本执行失败：sort-clash.py ($name)"
        return 1
    }

    # 读取清洗后的文本判断是否包含有效域名
    if [ -s "$domain_temp" ]; then
        # 为每行域名添加 +. 前缀（用于 DOMAIN-SUFFIX 后缀全匹配）
        sed "s/^/\\+\\./g" "$domain_temp" > "$mihomo_txt_file"
        
        # 编译为 .mrs 规则集并存入 mrs 文件夹
        "$MIHOMO_BIN" convert-ruleset domain text "$mihomo_txt_file" "$target_mrs_file"
        log "✅ 成功生成域名规则集：$target_mrs_file"
    else
        log "⚠️️ 警告：$txt_file 处理后无有效域名，跳过生成"
    fi

    # 清理过程中间文件
    rm -f "$mihomo_txt_file" "$domain_temp"
}

export -f process_rules log error
export PYTHON_CMD PROJECT_ROOT MRS_DIR MIHOMO_BIN CONFIG_FILE

main() {
    log "========================================"
    log "MyRules 构建开始"
    log "========================================"

    check_python
    load_config
    get_txt_files
    setup_mihomo_tool

    # 确保根目录下 mrs 文件夹存在
    mkdir -p "$MRS_DIR"

    TASK_DIR=$(mktemp -d)

    for txt_file in $TXT_FILES; do
        local filename name
        filename=$(basename "$txt_file")
        name="${filename%.*}"
        echo "$name|$txt_file" > "$TASK_DIR/task_${name}.txt"
    done

    ls "$TASK_DIR"/task_*.txt | xargs -P "$PARALLEL_PROCESSES" -I {} bash -c '
        task_file="{}"
        IFS="|" read -r name txt_file < "$task_file"
        process_rules "$name" "$txt_file"
    '

    log "========================================"
    log "✅ 所有规则处理完成！"
    log "========================================"
}

main
