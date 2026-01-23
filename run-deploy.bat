@echo off
chcp 65001 >nul
echo === 启动MRS规则集GitHub部署 ===
echo.

echo 选择部署方式：
echo [1] 使用批处理脚本（推荐）
echo [2] 修改PowerShell策略后使用PowerShell脚本
echo [3] 绕过执行策略运行PowerShell脚本
echo.

set /p choice="请选择 (1/2/3): "

if "%choice%"=="1" (
    echo 运行批处理部署脚本...
    call deploy-to-github.bat
) else if "%choice%"=="2" (
    echo 修改PowerShell执行策略为RemoteSigned...
    powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser"
    echo 执行策略已修改，现在可以运行PowerShell脚本了
    echo 请重新运行: .\deploy-to-github.ps1
    pause
) else if "%choice%"=="3" (
    echo 绕过执行策略运行PowerShell脚本...
    powershell -ExecutionPolicy Bypass -File deploy-to-github.ps1
) else (
    echo 无效选择
    pause
)