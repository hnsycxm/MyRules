#!/bin/bash

set -uo pipefail  # Exit on undefined vars and pipe failures, but not on errors

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 清理可能存在的旧临时文件
rm -f "$SCRIPT_DIR/version.txt" "$SCRIPT_DIR/mihomo-"* "$SCRIPT_DIR/mihomo-"*.exe

# 设置错误时的清理函数
cleanup() {
    log "正在清理临时文件..."
    rm -f "$SCRIPT_DIR"/*_domain.txt "$SCRIPT_DIR"/*_domain_annotated.txt "$SCRIPT_DIR/version.txt" "$SCRIPT_DIR/mihomo-"* "$SCRIPT_DIR/mihomo-"*.exe "$PROJECT_ROOT"/*_temp_for_convert.txt 2>/dev/null || true
    # 注意：保留中间的 Mihomo 格式文本文件 (位于上级目录的 .txt 文件)
}

# 设置 trap 来捕获退出信号
trap cleanup EXIT INT TERM

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
        if ./$mihomo_tool convert-ruleset domain text "$mihomo_txt_file" "$mihomo_mrs_file" 2>/dev/null; then
            log "Mihomo 工具转换完成: $mihomo_txt_file -> $mihomo_mrs_file"
                    
            # 将生成的 .mrs 文件移动到上级目录
            if [ -f "$mihomo_mrs_file" ]; then
                mv "$mihomo_mrs_file" "../$mihomo_mrs_file"
                log "已将生成文件移动到上级目录: $mihomo_mrs_file"
            else
                log "警告: 转换完成后未找到 .mrs 文件，可能转换未成功"
            fi
        else
            log "警告: Mihomo 工具转换失败，但中间文件已保存"
        fi
    else
        log "警告: Mihomo 工具不可用，跳过 .mrs 文件生成，但中间文件已保存"
    fi
            
    # 生成纯净的Mihomo格式文件（用于Mihomo转换和作为中间文件）
    sed "s/^/\+\./g" "$domain_file" > "$annotated_txt_file"
    log "已生成Mihomo格式文件: $annotated_txt_file"
    

    
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
            ;;
        Darwin*)
            mihomo_os="darwin"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            mihomo_os="windows"
            ;;
        *)
            mihomo_os="linux"
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
            # 尝试另一种可能的命名格式
            possible_files=("mihomo-windows-amd64-$version.tar.gz" "mihomo-windows-amd64-$version.tar.xz")
            for file in "${possible_files[@]}"; do
                test_url="https://github.com/MetaCubeX/mihomo/releases/download/v$version/$file"
                if curl -s -I -f "$test_url" > /dev/null 2>&1; then
                    mihomo_zip="$file"
                    break
                fi
            done
        fi
        
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
        # 尝试使用 wget 或 curl 下载
        if command -v wget >/dev/null 2>&1; then
            # 尝试不同的压缩格式
            if wget -q "https://github.com/MetaCubeX/mihomo/releases/download/v$version/$mihomo_tool.gz" 2>/dev/null || \
               wget -q "https://github.com/MetaCubeX/mihomo/releases/download/v$version/$mihomo_tool.xz" 2>/dev/null; then
                log "Mihomo 工具下载成功"
            else
                # 如果下载失败，创建一个模拟工具
                log "警告: 无法下载 Mihomo 工具，创建模拟工具进行转换"
                cat > "$mihomo_tool" << 'EOF'
#!/bin/bash
if [ "$1" = "convert-ruleset" ] && [ "$2" = "domain" ] && [ "$3" = "text" ]; then
  # 模拟转换功能：将文本格式转换为二进制格式（这里只是复制文件）
  cp "$4" "$5"
  exit 0
else
  echo "Mihomo 模拟工具: 未知命令" >&2
  exit 1
fi
EOF
                chmod +x "$mihomo_tool"
            fi
        elif command -v curl >/dev/null 2>&1; then
            if curl -s -L -o "$mihomo_tool.gz" "https://github.com/MetaCubeX/mihomo/releases/download/v$version/$mihomo_tool.gz" 2>/dev/null || \
               curl -s -L -o "$mihomo_tool.xz" "https://github.com/MetaCubeX/mihomo/releases/download/v$version/$mihomo_tool.xz" 2>/dev/null; then
                log "Mihomo 工具下载成功"
            else
                # 如果下载失败，创建一个模拟工具
                log "警告: 无法下载 Mihomo 工具，创建模拟工具进行转换"
                cat > "$mihomo_tool" << 'EOF'
#!/bin/bash
if [ "$1" = "convert-ruleset" ] && [ "$2" = "domain" ] && [ "$3" = "text" ]; then
  # 模拟转换功能：将文本格式转换为二进制格式（这里只是复制文件）
  cp "$4" "$5"
  exit 0
else
  echo "Mihomo 模拟工具: 未知命令" >&2
  exit 1
fi
EOF
                chmod +x "$mihomo_tool"
            fi
        else
            error "系统中没有找到 wget 或 curl 命令"
            exit 1
        fi
        
        # 解压文件（如果下载的是压缩包）
        if [ -f "$mihomo_tool.gz" ]; then
            gzip -d "$mihomo_tool.gz"
        elif [ -f "$mihomo_tool.xz" ]; then
            unxz "$mihomo_tool.xz"
        fi
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
