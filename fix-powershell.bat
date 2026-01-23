@echo off
echo === 修复PowerShell执行策略 ===
echo.

echo 当前执行策略：
powershell -Command "Get-ExecutionPolicy"
echo.

echo 修改执行策略为RemoteSigned（推荐）...
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser"

echo.
echo 执行策略已修改！
echo 现在你可以正常运行PowerShell脚本了。
echo.

echo 测试运行：
powershell -Command "Write-Host 'PowerShell脚本现在可以正常运行了！' -ForegroundColor Green"

echo.
pause