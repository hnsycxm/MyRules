#!/bin/bash
# script/build-combined-rules.sh (保持原文件名)
set -euo pipefail

SCRIPT_DIR=" $ (cd " $ (dirname " $ 0")"; pwd)"
PROJECT_ROOT=" $ (dirname " $ SCRIPT_DIR")"

# 日志函数
log() {
    echo " $ (date '+%Y-%m-%d %H:%M:%S') [INFO]  $ @"
}

error() {
    echo " $ (date '+%Y-%m-%d %H:%M:%S') [ERROR]  $ @" >&2
}

# 清理函数
cleanup() {
    log "清理临时文件..."
    rm -f " $ SCRIPT_DIR"/*.tmp " $ SCRIPT_DIR"/mihomo-* 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# 处理单个TXT文件
process_txt_file() {
    local txt_file=" $ 1"
    local base_name= $ (basename " $ txt_file" .txt)
    
    log "处理文件:  $ base_name"
    
    # 创建临时文件
    local temp_file= $ (mktemp)
    
    # 复制并修复换行符
    cp " $ txt_file" " $ temp_file"
    sed -i 's/\r $ //' " $ temp_file"
    
    # 使用Python脚本处理域名
    python " $ SCRIPT_DIR/../sort-clash.py" " $ temp_file"
    
    # 生成带+.前缀的Mihomo格式文件
    local mihomo_format_file=" $ PROJECT_ROOT/ $ {base_name}_temp_for_convert.txt"
    sed 's/^/+./' " $ temp_file" > " $ mihomo_format_file"
    
    # 生成MRS文件
    local mrs_file=" $ PROJECT_ROOT/ $ {base_name}.mrs"
    # 模拟Mihomo转换（实际使用时替换为真正的Mihomo工具）
    sed 's/^/+./' " $ temp_file" > " $ mrs_file"
    
    # 生成Mihomo格式文件（保留注释）
    local annotated_txt_file=" $ PROJECT_ROOT/ $ {base_name}.txt"
    sed 's/^/+./' " $ temp_file" > " $ annotated_txt_file"
    
    log "生成:  $ mihomo_format_file,  $ mrs_file 和  $ annotated_txt_file"
    
    # 清理临时文件
    rm -f " $ temp_file"
}

# 主流程
log "开始构建MRS文件..."

# 查找所有txt文件并处理
for txt_file in " $ PROJECT_ROOT/txt/"*.txt; do
    if [ -f " $ txt_file" ]; then
        process_txt_file " $ txt_file"
    fi
done

log "构建完成！"
