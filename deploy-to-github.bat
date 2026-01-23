@echo off
chcp 65001 >nul
echo === MRS规则集部署到GitHub ===
echo.

echo 检查Git是否安装...
git --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ✗ 错误: Git未安装或不在PATH中
    echo 请先安装Git: https://git-scm.com/downloads
    pause
    exit /b 1
)
echo ✓ Git已安装
echo.

if exist .git (
    echo ✓ Git仓库已存在
) else (
    echo ○ 初始化Git仓库...
    git init
    echo ✓ Git仓库已初始化
)
echo.

echo ○ 配置Git用户信息...
git config --global user.name >nul 2>&1
if %errorlevel% neq 0 (
    set /p gitName="请输入你的Git用户名: "
    git config --global user.name "%gitName%"
)

git config --global user.email >nul 2>&1
if %errorlevel% neq 0 (
    set /p gitEmail="请输入你的Git邮箱: "
    git config --global user.email "%gitEmail%"
)
echo ✓ Git用户信息已配置
echo.

echo ○ 添加文件到暂存区...
git add .
echo ✓ 文件已添加到暂存区
echo.

echo ○ 提交更改...
git commit -m "Initial commit: MRS规则集项目" -m "" -m "- 添加OKTV域名规则集" -m "- 配置GitHub Actions自动编译工作流" -m "- 设置.gitignore忽略编译输出文件"
if %errorlevel% equ 0 (
    echo ✓ 初始提交完成
) else (
    echo ○ 没有新的更改需要提交
)
echo.

echo === GitHub仓库设置 ===
echo.
echo 现在你需要创建一个GitHub仓库：
echo 1. 打开浏览器访问: https://github.com/new
echo 2. 仓库名称建议: MyRules 或 MRS-Rules
echo 3. 保持公开或设为私有
echo 4. 不要初始化README、.gitignore或license
echo.

set /p repoUrl="创建完成后，请输入你的GitHub仓库URL (例如: https://github.com/username/MyRules.git): "

if defined repoUrl (
    echo ○ 添加远程仓库...
    git remote add origin "%repoUrl%"
    echo ✓ 远程仓库已添加
    echo.

    echo ○ 推送到GitHub...
    git push -u origin main

    if %errorlevel% equ 0 (
        echo ✓ 代码已成功推送到GitHub！
        echo.
        echo 🎉 部署完成！
        echo.
        echo 现在每次修改OKTV.txt并推送后，GitHub Actions会自动编译生成OKTV.mrs文件。
        echo 你可以在仓库的Actions标签页查看编译状态。
    ) else (
        echo ✗ 推送失败，请检查仓库URL是否正确
    )
) else (
    echo 请先创建GitHub仓库，然后重新运行此脚本。
)

echo.
pause