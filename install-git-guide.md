# Git安装指南

## 问题描述
运行部署脚本时出现："Git未安装或不在PATH中"

## 解决方案

### 方法1：安装Git for Windows（推荐）

1. **下载安装程序**
   - 访问官网：https://git-scm.com/download/win
   - 或GitHub发布页：https://github.com/git-for-windows/git/releases/latest

2. **运行安装程序**
   - 双击下载的 `.exe` 文件
   - 点击 "Next" 继续默认设置
   - **重要设置**：
     - 选择 "Use Git from the Windows Command Prompt"
     - 选择 "Allow Git to be used by third-party tools"

3. **验证安装**
   - 打开命令提示符（Win+R → cmd）
   - 输入：`git --version`
   - 应该显示版本信息

### 方法2：使用Git客户端

如果你已经安装了其他Git客户端（如GitHub Desktop、TortoiseGit等）：

1. **检查PATH**
   - 右键"此电脑" → "属性" → "高级系统设置"
   - "环境变量" → "系统变量" → 找到"Path"
   - 编辑并添加Git的bin目录（如：`C:\Program Files\Git\cmd`）

2. **重启命令提示符**
   - 关闭并重新打开命令提示符窗口

### 方法3：便携版Git

如果不想安装到系统：

1. 下载便携版：https://git-scm.com/download/win (选择"Portable"版本)
2. 解压到任意目录
3. 在部署脚本中使用完整路径，或添加到PATH

## 安装后的验证

运行项目中的 `check-git.bat` 来验证Git是否正确安装。

## 常见问题

### Q: 仍然提示"Git未安装"
A: 重启命令提示符，或注销并重新登录Windows

### Q: PATH设置无效
A: 确保添加的是 `git.exe` 所在的目录，通常是：
- `C:\Program Files\Git\cmd`
- `C:\Program Files\Git\bin`

### Q: 权限问题
A: 以管理员身份运行命令提示符进行安装