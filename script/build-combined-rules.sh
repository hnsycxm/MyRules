#!/bin/bash

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 清理可能存在的旧临时文件
rm -f "$SCRIPT_DIR/version.txt" "$SCRIPT_DIR/mihomo-"* "$SCRIPT_DIR/mihomo-"*.exe

# 设置错误时的清理函数
cleanup() {
    log "检测到错误，正在清理临时文件..."
    rm -f "$SCRIPT_DIR"/*_domain.txt "$SCRIPT_DIR"/*_domain_annotated.txt "$SCRIPT_DIR/version.txt" "$SCRIPT_DIR/mihomo-"* "$SCRIPT_DIR/mihomo-"*.exe "$PROJECT_ROOT"/*_temp_for_convert.txt
    # 注意：保留中间的 Mihomo 格式文本文件 (位于上级目录的 .txt 文件)
}

# 设置 trap 来捕获错误和退出信号
trap cleanup ERR EXIT INT TERM

# 定义日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $@"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $@" >&2
}

# 获取 txt 目录下的所有 txt 文件
TXT_FILES=$(find "$PROJECT_ROOT/txt" -maxdepth 1 -name "*.txt" -type f)

# 函数：处理规则
process_rules() {
    local name=$1
    local txt_file=$2
    local script=$3
    local domain_file="${name}_domain.txt"
    local mihomo_txt_file="$PROJECT_ROOT/${name}_temp_for_convert.txt"
    local annotated_txt_file="$PROJECT_ROOT/${name}.txt"
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
    sed "s/^/\+\./g" "$domain_file" > "$mihomo_txt_file"
        
    # 检查Mihomo工具是否存在
    if [ -f "$mihomo_tool" ]; then
        ./"$mihomo_tool" convert-ruleset domain text "$mihomo_txt_file" "$mihomo_mrs_file"
        conversion_success=$?
        if [ $conversion_success -eq 0 ]; then
            log "Mihomo 工具转换完成: $mihomo_txt_file -> $mihomo_mrs_file"
                
            # 将生成的 .mrs 文件移动到上级目录
            mv "$mihomo_mrs_file" "../$mihomo_mrs_file"
            log "已将生成文件移动到上级目录: $mihomo_mrs_file"
        else
            error "Mihomo 工具转换失败: $mihomo_txt_file"
            log "警告: .mrs 文件未能生成，但中间文件已保存"
        fi
    else
        error "Mihomo 工具不可用: $mihomo_tool 不存在"
        log "警告: Mihomo 工具不可用，跳过 .mrs 文件生成，但中间文件已保存"
    fi
            
    # 生成纯净的Mihomo格式文件（用于Mihomo转换和作为中间文件）
    sed "s/^/\+\./g" "$domain_file" > "$annotated_txt_file"
    log "已生成Mihomo格式文件: $annotated_txt_file"
    
    # 创建带注释的Mihomo格式文件（用于人类阅读）
    if [ -f "$PROJECT_ROOT/${name}_annotated.txt" ]; then
        # 生成带注释的Mihomo格式文件（单独保存）
        comment_file="$PROJECT_ROOT/${name}_annotated.txt"
        annotated_mihomo_file="$PROJECT_ROOT/${name}_annotated_mihomo.txt"
        sed "s/^/\+\./g" "$comment_file" > "$annotated_mihomo_file"
        log "已生成带注释的Mihomo格式文件: $annotated_mihomo_file"
    fi
    
    # 删除临时转换文件
    rm -f "$mihomo_txt_file"
    log "已保留中间 Mihomo 格式文本文件: $annotated_txt_file (保存在根目录)"
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
    
    # 直接设置版本号，避免API调用问题
    version="1.19.19"
    
    if [ $? -ne 0 ]; then
        error "设置版本号失败"
        exit 1
    fi

    
    if [ "$mihomo_os" = "windows" ]; then
        mihomo_tool="mihomo-windows-amd64-$version.exe"
        # 尝试多个可能的文件名，因为不同版本的命名可能略有不同
        possible_files=("mihomo-windows-amd64-v$version.zip" "mihomo-windows-amd64-$version.zip" "mihomo-windows-amd64-v1-$version.zip")
        mihomo_zip=""
        for file in "${possible_files[@]}"; do
            test_url="https://github.com/MetaCubeX/mihomo/releases/download/v$version/$file"
            if curl -s -I -f "$test_url" > /dev/null 2>&1; then
                mihomo_zip="$file"
                break
            fi
        done
        
        if [ -z "$mihomo_zip" ]; then
            error "找不到可用的Mihomo Windows版本: v$version"
            exit 1
        fi
        
        curl -s -L -o "$mihomo_zip" "https://github.com/MetaCubeX/mihomo/releases/download/v$version/$mihomo_zip"
        if [ $? -ne 0 ]; then
            error "下载 Mihomo 工具失败"
            exit 1
        fi
        # 解压ZIP文件
        if command -v unzip >/dev/null 2>&1; then
            unzip -o "$mihomo_zip"
            rm -f "$mihomo_zip"
        else
            error "未找到unzip命令，无法解压文件"
            exit 1
        fi
        
        # 查找解压后的实际可执行文件
        actual_exe=$(ls mihomo-windows-amd64*.exe 2>/dev/null | head -n 1)
        if [ -n "$actual_exe" ] && [ "$actual_exe" != "$mihomo_tool" ]; then
            mv "$actual_exe" "$mihomo_tool"
        fi
        chmod +x "$mihomo_tool"
    else
        mihomo_tool="mihomo-$mihomo_os-amd64-$version"
        wget -q "https://github.com/MetaCubeX/mihomo/releases/download/v$version/$mihomo_tool.gz"
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
if [ -n "$TXT_FILES" ]; then
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
else
    log "未找到任何 txt 文件进行处理"
fi

log "脚本执行完成，中间文件已保留供后续使用"
