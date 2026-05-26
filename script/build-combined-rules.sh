#!/bin/bash
# MyRules 构建脚本
# 用于批量处理域名规则并生成 Mihomo 格式文件

set -e  # 遇到错误立即退出

# 切换到脚本所在目录
cd "$(cd "$(dirname "$0")" && pwd)" || exit 1
PROJECT_ROOT="$(pwd)/.."
CONFIG_FILE="$PROJECT_ROOT/config.yaml"
TASK_DIR=""

# 定义日志函数（在使用前定义）
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >&2
}

# 设置错误时的清理函数
cleanup() {
    log "检测到退出，正在清理临时文件..."
    rm -f ./*_domain.txt ./*_Mihomo.txt version.txt
    [ -n "$TASK_DIR" ] && rm -rf "$TASK_DIR" 2>/dev/null || true
}

# 设置 trap 来捕获错误和退出信号
trap cleanup EXIT INT TERM

# 检查 Python 是否安装
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

    python_version=$($PYTHON_CMD --version 2>&1 | awk '{print $2}')
    log "使用 Python 版本：$python_version"
}

# 读取配置文件中的并行进程数
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

# 获取 txt 目录下的所有 txt 文件
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

    log "找到以下规则文件:"
    echo "$TXT_FILES" | while read -r file; do
        log "  - $(basename "$file")"
    done
}

# 下载 Mihomo 工具
MIHOMO_TOOL=""
setup_mihomo_tool() {
    log "开始下载 Mihomo 工具"

    # 检测操作系统平台
    local platform mihomo_os
    platform="$(uname -s)"
    case "$platform" in
        Linux*)   mihomo_os="linux" ;;
        Darwin*)  mihomo_os="darwin" ;;
        CYGWIN*|MINGW*|MSYS*) mihomo_os="windows" ;;
        *)        mihomo_os="linux" ;;
    esac

    # 缓存目录
    local cache_dir="$PROJECT_ROOT/.cache"
    mkdir -p "$cache_dir"

    # 下载版本信息
    local version_file="$cache_dir/version.txt"
    if [ "$mihomo_os" = "windows" ]; then
        curl -s -L -o "$version_file" https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/version.txt
    else
        wget -q -O "$version_file" https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/version.txt
    fi

    if [ $? -ne 0 ]; then
        error "下载版本文件失败"
        exit 1
    fi

    local version
    version=$(cat "$version_file")

    # 构建工具名称
    if [ "$mihomo_os" = "windows" ]; then
        MIHOMO_TOOL="mihomo-windows-amd64-$version.exe"
    else
        MIHOMO_TOOL="mihomo-$mihomo_os-amd64-$version"
    fi

    # 检查缓存
    if [ -f "$cache_dir/$MIHOMO_TOOL" ]; then
        log "使用缓存的 Mihomo 工具：$cache_dir/$MIHOMO_TOOL"
        cp "$cache_dir/$MIHOMO_TOOL" "$PROJECT_ROOT/$MIHOMO_TOOL"
        chmod +x "$PROJECT_ROOT/$MIHOMO_TOOL"
        return 0
    fi

    # 下载工具
    local download_url="https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/$MIHOMO_TOOL.gz"
    if [ "$mihomo_os" = "windows" ]; then
        curl -s -L -o "$cache_dir/$MIHOMO_TOOL.gz" "$download_url"
    else
        wget -q -O "$cache_dir/$MIHOMO_TOOL.gz" "$download_url"
    fi

    if [ $? -ne 0 ]; then
        error "下载 Mihomo 工具失败"
        exit 1
    fi

    # 解压
    if [ "$mihomo_os" = "windows" ]; then
        gunzip "$cache_dir/$MIHOMO_TOOL.gz"
    else
        gzip -d "$cache_dir/$MIHOMO_TOOL.gz"
    fi

    chmod +x "$cache_dir/$MIHOMO_TOOL"
    cp "$cache_dir/$MIHOMO_TOOL" "$PROJECT_ROOT/$MIHOMO_TOOL"
    chmod +x "$PROJECT_ROOT/$MIHOMO_TOOL"
    log "Mihomo 工具已缓存：$cache_dir/$MIHOMO_TOOL"
    log "Mihomo 工具下载完成: $MIHOMO_TOOL"
}

# 函数：处理规则
process_rules() {
    local name=$1
    local txt_file=$2
    local domain_file="${name}_domain.txt"
    local mihomo_txt_file="${name}_Mihomo.txt"
    local mihomo_mrs_file="${name}.mrs"

    log "开始处理规则: $name"

    # 检查输入文件是否存在
    if [ ! -f "$txt_file" ]; then
        error "输入文件不存在: $txt_file"
        return 1
    fi

    # 复制并修复换行符
    cp "$txt_file" "$domain_file"
    sed -i 's/\r//' "$domain_file" 2>/dev/null || true

    # 调用 Python 脚本去重排序
    $PYTHON_CMD "sort-clash.py" "$domain_file" --config "$CONFIG_FILE"
    if [ $? -ne 0 ]; then
        error "Python 脚本执行失败：sort-clash.py"
        return 1
    fi
    log "✅ Python 脚本执行完成：$name"

    # 转换为 Mihomo 格式
    sed "s/^/\\+\\./g" "$domain_file" > "$mihomo_txt_file"
    ./"$MIHOMO_TOOL" convert-ruleset domain text "$mihomo_txt_file" "$mihomo_mrs_file"
    if [ $? -ne 0 ]; then
        error "Mihomo 工具转换失败: $mihomo_txt_file"
        return 1
    fi

    # 移动生成文件到项目根目录
    mv "$mihomo_mrs_file" "$PROJECT_ROOT/$mihomo_mrs_file"
    log "已生成规则文件：$PROJECT_ROOT/$mihomo_mrs_file"

    # 清理中间文件
    rm -f "$mihomo_txt_file"
    rm -f "$domain_file"
}

# 导出函数供 xargs 子进程使用
export -f process_rules log error
export PYTHON_CMD PROJECT_ROOT MIHOMO_TOOL CONFIG_FILE

# 主流程
main() {
    log "========================================"
    log "MyRules 构建开始"
    log "========================================"

    # 初始化
    check_python
    load_config
    get_txt_files
    setup_mihomo_tool

    # 创建临时目录存放任务
    TASK_DIR=$(mktemp -d)

    # 生成任务列表
    for txt_file in $TXT_FILES; do
        local filename name
        filename=$(basename "$txt_file")
        name="${filename%.*}"
        echo "$name|$txt_file" > "$TASK_DIR/task_${name}.txt"
        log "创建任务：$name"
    done

    # 并行处理所有规则文件
    log "开始批量处理规则文件..."
    log "并行进程数限制：$PARALLEL_PROCESSES"

    ls "$TASK_DIR"/task_*.txt | xargs -P "$PARALLEL_PROCESSES" -I {} bash -c '
        task_file="{}"
        IFS="|" read -r name txt_file < "$task_file"
        process_rules "$name" "$txt_file"
    '

    log "========================================"
    log "✅ 所有规则处理完成！"
    log "========================================"

    # 显示生成的文件
    log "生成的规则文件:"
    find "$PROJECT_ROOT" -maxdepth 1 -name "*.mrs" -type f | while read -r mrs_file; do
        local filesize
        filesize=$(du -h "$mrs_file" | cut -f1)
        log "  - $(basename "$mrs_file") ($filesize)"
    done

    log "脚本执行完成，临时文件将在退出时自动清理"
}

# 执行主流程
main
