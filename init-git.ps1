# 初始化Git仓库的PowerShell脚本
Write-Host "初始化Git仓库..." -ForegroundColor Green

# 检查git是否安装
try {
    $gitVersion = git --version
    Write-Host "Git版本: $gitVersion" -ForegroundColor Yellow
} catch {
    Write-Host "错误: Git未安装或不在PATH中" -ForegroundColor Red
    Write-Host "请先安装Git: https://git-scm.com/downloads" -ForegroundColor Red
    exit 1
}

# 初始化仓库
git init
Write-Host "Git仓库已初始化" -ForegroundColor Green

# 添加所有文件
git add .
Write-Host "文件已添加到暂存区" -ForegroundColor Green

# 初始提交
git commit -m "Initial commit: MRS规则集项目"
Write-Host "初始提交完成" -ForegroundColor Green

Write-Host ""
Write-Host "接下来你需要执行以下命令:" -ForegroundColor Cyan
Write-Host "1. 设置远程仓库: git remote add origin <你的GitHub仓库URL>" -ForegroundColor White
Write-Host "2. 推送到远程: git push -u origin main" -ForegroundColor White
Write-Host ""
Write-Host "或者运行批处理文件: .\init-git.bat" -ForegroundColor White

Read-Host "按Enter键继续"