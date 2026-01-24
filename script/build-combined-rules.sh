#!/bin/bash

# 切换到脚本所在目录
cd $(cd "$(dirname "$0")";pwd)

# 定义日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $@"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $@" >&2
}

# 获取 txt 目录下的所有 txt 文件
TXT_FILES=$(find ../txt -maxdepth 1 -name "*.txt" -type f)

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
    sed -i 's/\r//' "$domain_file"
    log "已修复换行符: $domain_file"

    python "$script" "$domain_file"
    if [ $? -ne 0 ]; then
        error "Python 脚本执行失败: $script"
        return 1
    fi
    log "Python 脚本执行完成: $script"

    # 转换为 Mihomo 格式
    sed "s/^/\\+\\./g" "$domain_file" > "$mihomo_txt_file"
    ./"$mihomo_tool" convert-ruleset domain text "$mihomo_txt_file" "$mihomo_mrs_file"
    if [ $? -ne 0 ]; then
        error "Mihomo 工具转换失败: $mihomo_txt_file"
        return 1
    fi
    log "Mihomo 工具转换完成: $mihomo_txt_file -> $mihomo_mrs_file"

    # 将生成的 .mrs 文件移动到上级目录
    mv "$mihomo_mrs_file" "../$mihomo_mrs_file"
    log "已将生成文件移动到上级目录: $mihomo_mrs_file"
    
    # 删除中间的 Mihomo 格式文本文件，只保留原始输入文件
    rm -f "../txt/$mihomo_txt_file"
    log "已删除中间 Mihomo 格式文本文件: $mihomo_txt_file"
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
    
    # 使用固定版本名称，不依赖版本信息
    version="latest"
    
    # 使用通用的工具名称，避免版本依赖
    if [ "$mihomo_os" = "windows" ]; then
        mihomo_tool="mihomo-windows-amd64.exe"
        # 尝试下载预编译的最新版本
        if command -v curl >/dev/null 2>&1; then
            curl -s -L -o "$mihomo_tool.gz" "https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-$mihomo_os-amd64.exe.gz"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O "$mihomo_tool.gz" "https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-$mihomo_os-amd64.exe.gz"
        else
            error "系统缺少curl或wget命令"
            exit 1
        fi
        if [ $? -ne 0 ]; then
            error "下载 Mihomo 工具失败"
            exit 1
        fi
        gunzip "$mihomo_tool.gz"
        chmod +x "$mihomo_tool"
    else
        mihomo_tool="mihomo-$mihomo_os-amd64"
        # 尝试下载预编译的最新版本
        if command -v wget >/dev/null 2>&1; then
            wget -q -O "$mihomo_tool.gz" "https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-$mihomo_os-amd64.gz"
        elif command -v curl >/dev/null 2>&1; then
            curl -s -L -o "$mihomo_tool.gz" "https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-$mihomo_os-amd64.gz"
        else
            error "系统缺少curl或wget命令"
            exit 1
        fi
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
setup_mihomo_tool

# 并行处理所有检测到的 txt 文件
for txt_file in $TXT_FILES; do
    # 从文件名获取基本名称
    filename=$(basename "$txt_file")
    name="${filename%.*}"
    
    # 统一使用 sort-clash.py 处理通用域名列表
    script="sort-clash.py"
    
    process_rules "$name" "$txt_file" "$script" &
done

# 等待所有规则并行处理完成
wait

# 清理缓存文件
rm -rf ./*_domain.txt "$mihomo_tool"
log "脚本执行完成，已清理临时文件"
