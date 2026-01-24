# Rules

这是一个规则管理项目，用于生成和维护各类过滤规则。

## 项目特点

- 自动化构建规则文件
- 定时更新机制
- 支持手动触发更新

## 规则格式

支持多种域名格式，包括：
- 纯域名格式：`example.com`
- 通配符格式：`+.example.com`
- 脚本会自动验证域名格式的有效性并进行去重排序

## 部署到GitHub

要将此项目部署到GitHub，请按以下步骤操作：

### 1. 创建GitHub仓库

1. 登录GitHub账户
2. 点击"New repository"按钮
3. 输入仓库名称（例如：my-rules）
4. 选择Public或Private
5. 不要初始化仓库（不勾选README、.gitignore或license）

### 2. 上传代码

```bash
# 初始化本地仓库
git init
git add .
git commit -m "Initial commit"

# 添加远程仓库地址（替换your-username和repo-name）
git remote add origin https://github.com/your-username/repo-name.git

# 推送代码
git branch -M main
git push -u origin main
```

### 3. 自动化功能

此项目已配置GitHub Actions自动化工作流：
- 每天北京时间上午8:00自动更新规则
- 当特定文件发生变更时自动触发更新
- 支持手动触发更新
- 生成与原文件同名的`.mrs`二进制格式文件
- 不再依赖外部版本信息，也不生成中间的`version.txt`等临时文件

## 工作流说明

项目中的`.github/workflows/auto-update.yml`文件配置了自动化流程：
- `schedule`触发器：每天定时执行
- `push`触发器：监听特定文件路径变更
- `workflow_dispatch`触发器：支持手动触发

## 构建脚本

`script/build-combined-rules.sh`脚本负责构建规则文件。

## 文件结构

- `script/` - 存放构建脚本
- `txt/` - 存放源规则文件
- `.github/workflows/` - 存放GitHub Actions工作流配置

## 维护

项目会自动保持更新，您也可以随时手动触发更新或修改规则文件。