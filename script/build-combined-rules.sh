#!/bin/bash

# 切换到脚本所在目录
cd $(cd "$(dirname "$0")";pwd)

# --- 配置区域 ---
MAX_JOBS=4  # 设置并发线程数，GitHub Actions 建议设为 2 或 4
TXT_DIR="../txt"
# ----------------

# 定义日志函数
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $@"; }
error() { echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $@" >&2; }

# 清理临时文件的函数
cleanup() {
    log "正在清理临时文件..."
    rm -f ./*_domain.txt ./*_Mihomo.txt version.txt mihomo-* mihomo-*.exe
}

# 捕获信号并清理
trap cleanup EXIT ERR INT TERM

# 下载 Mihomo 工具的函数
setup_mihomo_tool() {
    log "开始检查/下载 Mihomo 工具"
    platform="$(uname -s)"
    case "$platform" in
        Linux*)   mihomo_os="linux";;
        Darwin*)  mihomo_os="darwin";;
        CYGWIN*|MINGW*|MSYS*) mihomo_os="windows";;
        *)        mihomo_os="linux";;
    esac
    
    # 获取版本信息
    wget -q https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/version.txt
    if [ $? -ne 0 ]; then error "下载版本文件失败"; exit 1; fi
    version=$(cat version.txt)
    
    if [ "$mihomo_os" = "windows" ]; then
        mihomo_tool="mihomo-windows-amd64-$version.exe"
        [ ! -f "$mihomo_tool" ] && curl -s -L -o "$mihomo_tool.gz" "https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/$mihomo_tool.gz" && gunzip "$mihomo_tool.gz"
    else
        mihomo_tool="mihomo-$mihomo_os-amd64-$version"
        [ ! -f "$mihomo_tool" ] && wget -q "https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/$mihomo_tool.gz" && gzip -d "$mihomo_tool.gz"
    fi
    
    chmod +x "$mihomo_tool"
    echo "$mihomo_tool"
}

# 定义核心处理逻辑函数，导出给 xargs 使用
process_rules_parallel() {
    local txt_file="$1"
    local mihomo_tool="$2"
    local script="sort-clash.py"
    
    filename=$(basename "$txt_file")
    name="${filename%.*}"
    domain_file="${name}_domain.txt"
    mihomo_txt_file="${name}_Mihomo.txt"
    mihomo_mrs_file="${name}.mrs"

    echo "[$(date '+%H:%M:%S')] 正在处理: $filename"
    
    # 准备工作文件
    cp "$txt_file" "$domain_file"
    sed -i 's/\r//' "$domain_file"

    # 1. 执行 Python 脚本清洗（已包含 IP 支持逻辑）
    python3 "$script" "$domain_file" > /dev/null 2>&1
    if [ $? -ne 0 ]; then echo "  [!] $filename: Python 脚本失败"; return 1; fi
    
    # 2. 自动判断规则类型：通过正则匹配判断是否包含 IP/CIDR
    if grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}|^([0-9a-fA-F]{1,4}:){1,7}' "$domain_file"; then
        rule_type="ip-cidr"
        cp "$domain_file" "$mihomo_txt_file" # IP 规则直接复制，不加 +.
    else
        rule_type="domain"
        sed "s/^/\+\./g" "$domain_file" > "$mihomo_txt_file" # 域名规则增加匹配前缀
    fi
    
    # 3. 根据判断的类型进行动态编译
    ./$mihomo_tool convert-ruleset "$rule_type" text "$mihomo_txt_file" "$mihomo_mrs_file" > /dev/null 2>&1
    if [ $? -ne 0 ]; then echo "  [!] $filename: MRS 转换失败"; return 1; fi

    # 4. 移动结果并清理中间文件
    mv "$mihomo_mrs_file" "../$mihomo_mrs_file"
    rm -f "$domain_file" "$mihomo_txt_file"
    
    echo "[$(date '+%H:%M:%S')] 完成: $name.mrs"
}

# 导出函数供子 shell (xargs) 调用
export -f process_rules_parallel
export -f log

# --- 主流程 ---

# 1. 环境准备
MIHOMO_TOOL=$(setup_mihomo_tool)
log "使用工具: $MIHOMO_TOOL"

# 2. 获取文件列表并启动并行任务
# 使用 xargs -P 实现多线程控制
find "$TXT_DIR" -maxdepth 1 -name "*.txt" -type f | \
xargs -I {} -P "$MAX_JOBS" bash -c 'process_rules_parallel "$@"' _ {} "$MIHOMO_TOOL"

log "所有规则处理任务执行完毕！"