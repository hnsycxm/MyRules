@echo off
chcp 65001 >nul
echo === 检查Git安装状态 ===
echo.

echo 正在检查Git安装...
git --version >nul 2>&1
if %errorlevel% equ 0 (
    echo ✓ Git已正确安装！
    for /f "tokens=*" %%i in ('git --version') do echo   版本: %%i
    echo.
    echo 现在可以运行部署脚本了：
    echo   .\run-deploy.bat
    goto :end
) else (
    echo ✗ Git未安装或不在PATH中
    echo.
    echo 请按以下步骤安装Git：
    echo.
    echo 1. 下载Git for Windows：
    echo    访问: https://git-scm.com/download/win
    echo    或: https://github.com/git-for-windows/git/releases/latest
    echo.
    echo 2. 运行安装程序（推荐选项）：
    echo    □ Git Bash Here
    echo    □ Git GUI Here
    echo    □ Associate .git* files with Git
    echo    □ Associate .sh files with Git Bash
    echo    ✓ Use Git from the Windows Command Prompt  [重要]
    echo    □ Use Git and optional Unix tools from Windows Command Prompt
    echo    □ Use bundled OpenSSH
    echo    □ Use external OpenSSH
    echo    □ Enable experimental support for pseudo consoles
    echo    □ Enable experimental built-in file system monitor
    echo    ✓ Allow Git to be used by third-party tools [重要]
    echo.
    echo 3. 安装完成后，关闭并重新打开命令提示符
    echo.
    echo 4. 重新运行此检查脚本
    echo.
    echo 或者，如果你是开发者且已安装其他Git客户端：
    echo - 检查环境变量PATH是否包含Git安装路径
    echo - 通常路径类似: C:\Program Files\Git\cmd
    echo.
)

:end
echo.
pause