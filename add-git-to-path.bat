@echo off
chcp 65001 >nul
echo === 永久添加Git到系统PATH ===
echo.

echo 注意：此操作需要管理员权限
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ✗ 需要管理员权限运行此脚本
    echo 请右键"以管理员身份运行"
    pause
    exit /b 1
)

set GIT_PATH=D:\Kaola\PortableGit
set GIT_CMD=%GIT_PATH%\cmd
set GIT_BIN=%GIT_PATH%\bin

echo 检查Git目录...
if not exist "%GIT_CMD%\git.exe" (
    if not exist "%GIT_BIN%\git.exe" (
        echo ✗ 未找到git.exe，请检查安装路径
        pause
        exit /b 1
    )
)

echo ✓ 找到Git目录: %GIT_PATH%
echo.

echo 正在添加Git到系统PATH...

:: 获取当前PATH
for /f "tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "CURRENT_PATH=%%b"

:: 检查是否已存在
echo %CURRENT_PATH% | find /i "%GIT_CMD%" >nul
if %errorlevel% equ 0 (
    echo ✓ Git cmd路径已在PATH中
) else (
    echo 添加Git cmd路径...
    set "NEW_PATH=%CURRENT_PATH%;%GIT_CMD%"
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path /t REG_EXPAND_SZ /d "%NEW_PATH%" /f >nul
    if %errorlevel% equ 0 (
        echo ✓ Git cmd路径添加成功
    ) else (
        echo ✗ 添加Git cmd路径失败
    )
)

echo %CURRENT_PATH% | find /i "%GIT_BIN%" >nul
if %errorlevel% equ 0 (
    echo ✓ Git bin路径已在PATH中
) else (
    echo 添加Git bin路径...
    set "NEW_PATH=%NEW_PATH%;%GIT_BIN%"
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path /t REG_EXPAND_SZ /d "%NEW_PATH%" /f >nul
    if %errorlevel% equ 0 (
        echo ✓ Git bin路径添加成功
    ) else (
        echo ✗ 添加Git bin路径失败
    )
)

echo.
echo 刷新环境变量...
:: 通知系统环境变量已更改
powershell -Command "& { [System.Environment]::SetEnvironmentVariable('Path', [System.Environment]::GetEnvironmentVariable('Path', 'Machine'), 'Machine') }" >nul 2>&1

echo.
echo 测试Git...
git --version >nul 2>&1
if %errorlevel% equ 0 (
    echo ✓ Git PATH永久修复成功！
    for /f "tokens=*" %%i in ('git --version') do echo   版本: %%i
    echo.
    echo 现在可以在任何命令行窗口使用Git了！
    echo 可以运行: .\run-deploy.bat
) else (
    echo ✗ Git测试失败，可能需要重启电脑
    echo 或手动检查PATH设置
)

echo.
echo 提示：如果Git仍然无法使用，请重启电脑使PATH生效
echo.
pause