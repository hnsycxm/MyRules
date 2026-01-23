@echo off
echo 初始化Git仓库...
git init
git add .
git commit -m "Initial commit: MRS规则集项目"

echo.
echo Git仓库已初始化完成！
echo 接下来你需要：
echo 1. 设置远程仓库：git remote add origin ^<你的GitHub仓库URL^>
echo 2. 推送到远程：git push -u origin main
echo.
pause