@echo off
chcp 65001 >nul
echo === 简易GitHub部署指南 ===
echo.

echo 步骤1: 安装Git
echo ──────────────────
echo 如果还没安装Git，请先运行: .\check-git.bat
echo 按照提示安装Git for Windows
echo.
echo.

echo 步骤2: 创建GitHub仓库
echo ──────────────────
echo 1. 打开浏览器访问: https://github.com/new
echo 2. 仓库名称: MyRules (或任意名称)
echo 3. 保持公开或设为私有
echo 4. 不要初始化README、.gitignore或license
echo 5. 点击"Create repository"
echo.
echo.

echo 步骤3: 获取仓库URL
echo ──────────────────
echo 创建完成后，复制仓库URL，格式如下：
echo https://github.com/你的用户名/MyRules.git
echo.
echo.

echo 步骤4: 手动部署
echo ──────────────────
echo 安装Git后，在此目录打开命令提示符，执行：
echo.
echo git init
echo git add .
echo git commit -m "Initial commit: MRS规则集项目"
echo git remote add origin [你的仓库URL]
echo git push -u origin main
echo.
echo.

echo 或者使用自动脚本（推荐）:
echo ──────────────────
echo 安装Git后，运行: .\run-deploy.bat
echo.
echo.

echo 相关文件:
echo ──────────────────
echo check-git.bat         - 检查Git安装状态
echo fix-git-path.bat      - 临时修复Git PATH
echo add-git-to-path.bat   - 永久添加Git到系统PATH（需管理员权限）
echo run-deploy.bat        - 自动部署脚本
echo install-git-guide.md  - 详细安装指南
echo.
echo 如果已安装便携版Git但PATH有问题：
echo 1. 运行: .\fix-git-path.bat (临时修复)
echo 2. 或运行: .\add-git-to-path.bat (永久修复，需要管理员权限)
echo.

pause