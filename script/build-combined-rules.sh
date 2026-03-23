#!/bin/bash
# MyRules 构建脚本
# 用于批量处理域名规则并生成 Mihomo 格式文件

set -e  # 遇到错误立即退出

# 切换到脚本所在目录
cd "$(cd "$(dirname "$0")" && pwd)" || exit 1
PROJECT_ROOT="$(pwd)/.."

# 清理可能存在的旧临时文件
rm -f version.txt mihomo-* mihomo-*.exe

# 设置错误时的清理函数
cleanup() {
    log "检测到错误，正在清理临时文件..."
    rm -f ./*_domain.txt ./*_Mihomo.txt version.txt mihomo-* mihomo-*.exe
}

# 设置 trap 来捕获错误和退出信号
trap cleanup ERR EXIT INT TERM

# 定义日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >&2
}

# 检查 Python 是否安装
check_python() {
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &> /dev/null; then
        PYTHON_CMD="python"
    else
        error "未找到 Python，请先安装 Python 3.7+"
        exit 1
    fi
    
    # 检查 Python 版本
    python_version=$($PYTHON_CMD --version 2>&1 | awk '{print $2}')
    log "使用 Python 版本：$python_version"
}

# 获取 txt 目录下的所有 txt 文件
TXT_DIR="$PROJECT_ROOT/txt"
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

# 函数：处理规则
process_rules() {
    local name=$1
    local txt_file=$2
    local script=$3
    local domain_file="${name}_domain.txt"
    local mihomo_txt_file="${name}_Mihomo.txt"
    local mihomo_mrs_file="${name}.mrs"

    log "开始处理规则: $name"
    
    # 检查输入文件是否存在
    if [ ! -f "$txt_file" ]; then
        error "输入文件不存在: $txt_file"
        return 1
    fi
    
    # 复制现有的 txt 文件到临时处理文件
    cp "$txt_file" "$domain_file"
    log "已复制现有规则文件: $txt_file -> $domain_file"

    # 修复换行符并调用对应的 Python 脚本去重排序
    sed -i 's/\r//' "$domain_file" 2>/dev/null || true
    log "已修复换行符：$domain_file"
    
    $PYTHON_CMD "$script" "$domain_file"
    if [ $? -ne 0 ]; then
        error "Python 脚本执行失败：$script"
        return 1
    fi
    log "✅ Python 脚本执行完成：$script"

    # 转换为 Mihomo 格式
    sed "s/^/\\+\\./g" "$domain_file" > "$mihomo_txt_file"
    ./"$mihomo_tool" convert-ruleset domain text "$mihomo_txt_file" "$mihomo_mrs_file"
    if [ $? -ne 0 ]; then
        error "Mihomo 工具转换失败: $mihomo_txt_file"
        return 1
    fi
    log "Mihomo 工具转换完成: $mihomo_txt_file -> $mihomo_mrs_file"

    # 将生成的 .mrs 文件移动到上级目录
    mv "$mihomo_mrs_file" "$PROJECT_ROOT/$mihomo_mrs_file"
    log "已生成规则文件：$PROJECT_ROOT/$mihomo_mrs_file"
    
    # 删除中间的 Mihomo 格式文本文件，只保留原始输入文件
    rm -f "$mihomo_txt_file"
    log "已删除中间文件：$mihomo_txt_file"
    
    # 如果不保留临时文件，则删除
    if [ "${KEEP_TEMP_FILES:-false}" = "false" ]; then
        rm -f "$domain_file"
        log "已清理临时文件：$domain_file"
    fi
}

# 下载 Mihomo 工具
setup_mihomo_tool() {
    log "开始下载 Mihomo 工具"
    
    # 检测操作系统平台
    platform="$(uname -s)"
    case "$platform" in
        Linux*)
            mihomo_os="linux"
            downloader="wget -q"
            unzip_cmd="gzip -d"
            ;;
        Darwin*)
            mihomo_os="darwin"
            downloader="curl -s -L -o"
            unzip_cmd="gzip -d"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            mihomo_os="windows"
            downloader="curl -s -L -o"
            unzip_cmd="gunzip"
            ;;
        *)
            mihomo_os="linux"
            downloader="wget -q"
            unzip_cmd="gzip -d"
            ;;
    esac
    
    # 根据操作系统选择合适的 Mihomo 版本
    if [ "$mihomo_os" = "windows" ]; then
        # Windows 系统使用 curl 下载版本信息
        curl -s -L -o version.txt https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/version.txt
    else
        wget -q https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/version.txt
    fi
    
    if [ $? -ne 0 ]; then
        error "下载版本文件失败"
        exit 1
    fi

    version=$(cat version.txt)
    
    if [ "$mihomo_os" = "windows" ]; then
        mihomo_tool="mihomo-windows-amd64-$version.exe"
        curl -s -L -o "$mihomo_tool" "https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/$mihomo_tool.gz"
        if [ $? -ne 0 ]; then
            error "下载 Mihomo 工具失败"
            exit 1
        fi
        gunzip "$mihomo_tool.gz"
        chmod +x "$mihomo_tool"
    else
        mihomo_tool="mihomo-$mihomo_os-amd64-$version"
        wget -q "https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/$mihomo_tool.gz"
        if [ $? -ne 0 ]; then
            error "下载 Mihomo 工具失败"
            exit 1
        fi

        gzip -d "$mihomo_tool.gz"
        chmod +x "$mihomo_tool"
    fi
    
    log "Mihomo 工具下载完成: $mihomo_tool"
}

# 主流程
main() {
    log "========================================"
    log "MyRules 构建开始"
    log "========================================"
    
    # 检查 Python
    check_python
    
    # 下载 Mihomo 工具
    setup_mihomo_tool
    
    # 并行处理所有规则文件
    log "开始批量处理规则文件..."
    for txt_file in $TXT_FILES; do
        # 从文件名获取基本名称
        filename=$(basename "$txt_file")
        name="${filename%.*}"
        
        # 统一使用 sort-clash.py 处理通用域名列表
        script="sort-clash.py"
        
        log "创建后台任务：$name"
        process_rules "$name" "$txt_file" "$script" &
    done
    
    # 等待所有规则并行处理完成
    wait
    
    log "========================================"
    log "✅ 所有规则处理完成！"
    log "========================================"
    
    # 显示生成的文件
    log "生成的规则文件:"
    find "$PROJECT_ROOT" -maxdepth 1 -name "*.mrs" -type f | while read -r mrs_file; do
        filesize=$(du -h "$mrs_file" | cut -f1)
        log "  - $(basename "$mrs_file") ($filesize)"
    done
    
    log "脚本执行完成，临时文件将在退出时自动清理"
}

# 执行主流程
main
