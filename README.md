# MyRules - MRS规则集

这是一个基于[Mihomo](https://github.com/MetaCubeX/mihomo)的域名规则集项目，使用GitHub Actions自动编译。

## 项目结构

- `OKTV.txt` - 域名规则源文件
- `OKTV.mrs` - 编译后的二进制规则文件（自动生成）
- `.github/workflows/compile.yml` - GitHub Actions编译工作流

## 使用方法

### 1. 部署到GitHub

运行部署脚本：
```bash
# PowerShell (推荐)
.\deploy-to-github.ps1

# 或批处理文件
.\deploy-to-github.bat
```

### 2. 编辑规则

直接编辑 `OKTV.txt` 文件，添加或删除域名规则。每行一个域名，格式如下：
```
+.example.com
+.subdomain.example.com
```

### 3. 自动编译

推送更改到GitHub后，GitHub Actions会自动：
1. 下载Mihomo内核
2. 编译 `OKTV.txt` → `OKTV.mrs`
3. 提交编译结果到仓库

### 4. 使用编译后的规则

在Mihomo配置中使用：
```yaml
rule-providers:
  oktv:
    type: http
    behavior: domain
    url: "https://raw.githubusercontent.com/你的用户名/你的仓库名/main/OKTV.mrs"
    path: ./rules/OKTV.mrs
```

## 开发

- 规则文件：`OKTV.txt`
- 工作流：`.github/workflows/compile.yml`
- 编译输出：`OKTV.mrs`（自动生成，不需要手动编辑）

## 许可证

请根据需要添加合适的许可证。