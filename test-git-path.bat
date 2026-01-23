@echo off
chcp 65001 >nul
echo === 测试Git路径 ===
echo.

set GIT_PATH=D:\Kaola\PortableGit
set GIT_CMD=%GIT_PATH%\cmd
set GIT_BIN=%GIT_PATH%\bin

echo 检查目录结构:
echo ──────────────────
echo Git根目录: %GIT_PATH%
if exist "%GIT_PATH%" (
    echo ✓ 目录存在
) else (
    echo ✗ 目录不存在
)

echo Git cmd目录: %GIT_CMD%
if exist "%GIT_CMD%" (
    echo ✓ cmd目录存在
    if exist "%GIT_CMD%\git.exe" (
        echo ✓ git.exe 存在于cmd目录
    ) else (
        echo ✗ git.exe 不存在于cmd目录
    )
) else (
    echo ✗ cmd目录不存在
)

echo Git bin目录: %GIT_BIN%
if exist "%GIT_BIN%" (
    echo ✓ bin目录存在
    if exist "%GIT_BIN%\git.exe" (
        echo ✓ git.exe 存在于bin目录
    ) else (
        echo ✗ git.exe 不存在于bin目录
    )
) else (
    echo ✗ bin目录不存在
)

echo.
echo 测试直接运行:
echo ──────────────────
if exist "%GIT_CMD%\git.exe" (
    echo 测试cmd目录的git:
    "%GIT_CMD%\git.exe" --version
) else if exist "%GIT_BIN%\git.exe" (
    echo 测试bin目录的git:
    "%GIT_BIN%\git.exe" --version
) else (
    echo ✗ 未找到git.exe
)

echo.
echo 测试PATH中的git:
git --version >nul 2>&1
if %errorlevel% equ 0 (
    echo ✓ PATH中的Git工作正常
    for /f "tokens=*" %%i in ('git --version') do echo   版本: %%i
) else (
    echo ✗ PATH中的Git无法运行
    echo 需要修复PATH
)

echo.
pause