# 部署到GitHub的PowerShell脚本
Write-Host "=== MRS规则集部署到GitHub ===" -ForegroundColor Cyan
Write-Host ""

# 检查git是否安装
try {
    $gitVersion = git --version
    Write-Host "✓ Git版本: $gitVersion" -ForegroundColor Green
} catch {
    Write-Host "✗ 错误: Git未安装或不在PATH中" -ForegroundColor Red
    Write-Host "请先安装Git: https://git-scm.com/downloads" -ForegroundColor Red
    exit 1
}

# 检查是否已有git仓库
if (Test-Path ".git") {
    Write-Host "✓ Git仓库已存在" -ForegroundColor Green
} else {
    Write-Host "○ 初始化Git仓库..." -ForegroundColor Yellow
    git init
    Write-Host "✓ Git仓库已初始化" -ForegroundColor Green
}

# 配置用户信息（如果需要）
Write-Host "○ 配置Git用户信息..." -ForegroundColor Yellow
$gitName = git config --global user.name
$gitEmail = git config --global user.email

if (-not $gitName) {
    Write-Host "请输入你的Git用户名:" -ForegroundColor Yellow
    $gitName = Read-Host
    git config --global user.name $gitName
}

if (-not $gitEmail) {
    Write-Host "请输入你的Git邮箱:" -ForegroundColor Yellow
    $gitEmail = Read-Host
    git config --global user.email $gitEmail
}

Write-Host "✓ Git用户信息已配置: $gitName <$gitEmail>" -ForegroundColor Green

# 添加文件到暂存区
Write-Host "○ 添加文件到暂存区..." -ForegroundColor Yellow
git add .
Write-Host "✓ 文件已添加到暂存区" -ForegroundColor Green

# 提交更改
Write-Host "○ 提交更改..." -ForegroundColor Yellow
git commit -m "Initial commit: MRS规则集项目

- 添加OKTV域名规则集
- 配置GitHub Actions自动编译工作流
- 设置.gitignore忽略编译输出文件"

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ 初始提交完成" -ForegroundColor Green
} else {
    Write-Host "○ 没有新的更改需要提交" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== GitHub仓库设置 ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "现在你需要创建一个GitHub仓库：" -ForegroundColor White
Write-Host "1. 打开浏览器访问: https://github.com/new" -ForegroundColor White
Write-Host "2. 仓库名称建议: MyRules 或 MRS-Rules" -ForegroundColor White
Write-Host "3. 保持公开或设为私有" -ForegroundColor White
Write-Host "4. 不要初始化README、.gitignore或license" -ForegroundColor White
Write-Host ""

$repoUrl = Read-Host "创建完成后，请输入你的GitHub仓库URL (例如: https://github.com/username/MyRules.git)"

if ($repoUrl) {
    # 添加远程仓库
    Write-Host "○ 添加远程仓库..." -ForegroundColor Yellow
    git remote add origin $repoUrl
    Write-Host "✓ 远程仓库已添加" -ForegroundColor Green

    # 推送到GitHub
    Write-Host "○ 推送到GitHub..." -ForegroundColor Yellow
    git push -u origin main

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ 代码已成功推送到GitHub！" -ForegroundColor Green
        Write-Host ""
        Write-Host "🎉 部署完成！" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "现在每次修改OKTV.txt并推送后，GitHub Actions会自动编译生成OKTV.mrs文件。" -ForegroundColor White
        Write-Host "你可以在仓库的Actions标签页查看编译状态。" -ForegroundColor White
    } else {
        Write-Host "✗ 推送失败，请检查仓库URL是否正确" -ForegroundColor Red
    }
} else {
    Write-Host "请先创建GitHub仓库，然后重新运行此脚本。" -ForegroundColor Yellow
}

Read-Host "按Enter键退出"