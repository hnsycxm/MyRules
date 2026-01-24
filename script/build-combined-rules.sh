#!/bin/bash

# 切换到脚本所在目录
cd $(cd "$(dirname "$0")";pwd)

MAX_JOBS=4  # 并发数
TXT_DIR="../txt"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $@"; }
error() { echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $@" >&2; }

cleanup() {
    log "执行清理..."
    rm -f ./*_domain.txt ./*_Mihomo.txt version.txt mihomo-*
}
trap cleanup EXIT ERR

setup_mihomo_tool() {
    platform="$(uname -s)"
    mihomo_os="linux"
    [[ "$platform" == "Darwin"* ]] && mihomo_os="darwin"
    
    wget -q https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/version.txt
    version=$(cat version.txt)
    tool="mihomo-$mihomo_os-amd64-$version"
    
    if [ ! -f "$tool" ]; then
        log "下载工具: $tool"
        wget -q "https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/$tool.gz"
        gzip -d "$tool.gz"
        chmod +x "$tool"
    fi
    echo "$tool"
}

process_single_file() {
    local txt_file="$1"
    local tool="$2"
    name=$(basename "$txt_file" .txt)
    
    echo "[处理中] $name"
    cp "$txt_file" "${name}_domain.txt"
    sed -i 's/\r//' "${name}_domain.txt"
    
    python3 sort-clash.py "${name}_domain.txt" > /dev/null 2>&1
    sed "s/^/\\+\\./g" "${name}_domain.txt" > "${name}_Mihomo.txt"
    ./"$tool" convert-ruleset domain text "${name}_Mihomo.txt" "../${name}.mrs" > /dev/null 2>&1
    
    rm -f "${name}_domain.txt" "${name}_Mihomo.txt"
}

export -f process_single_file
export -f log

TOOL_NAME=$(setup_mihomo_tool)
log "开始并行构建..."

find "$TXT_DIR" -name "*.txt" | xargs -I {} -P "$MAX_JOBS" bash -c "process_single_file '{}' '$TOOL_NAME'"

log "构建完成！"
