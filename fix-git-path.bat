@echo off
chcp 65001 >nul
echo === 修复Git PATH ===
echo.

set GIT_PATH=D:\Kaola\PortableGit
set GIT_CMD=%GIT_PATH%\cmd
set GIT_BIN=%GIT_PATH%\bin

echo 检查便携版Git目录...
if not exist "%GIT_CMD%\git.exe" (
    if not exist "%GIT_BIN%\git.exe" (
        echo ✗ 在 %GIT_PATH% 中未找到git.exe
        echo 请确认Git安装路径是否正确
        goto :error
    )
)

echo ✓ 找到Git安装目录: %GIT_PATH%
echo.

echo 临时添加Git到PATH...
set "PATH=%GIT_CMD%;%GIT_BIN%;%PATH%"

echo 测试Git...
git --version >nul 2>&1
if %errorlevel% equ 0 (
    echo ✓ Git PATH修复成功！
    for /f "tokens=*" %%i in ('git --version') do echo   版本: %%i
    echo.
    echo 现在可以运行部署脚本了：
    echo   .\run-deploy.bat
    goto :success
) else (
    echo ✗ Git仍然无法运行
    goto :error
)

:success
echo.
echo 注意：此修复只在当前命令行窗口有效
echo 如果想永久修复，请手动添加以下路径到系统PATH：
echo %GIT_CMD%
echo %GIT_BIN%
echo.
pause
exit /b 0

:error
echo.
echo 修复失败，请检查：
echo 1. Git安装路径是否正确
echo 2. Git文件是否完整
echo 3. 尝试重新安装Git
echo.
pause
exit /b 1