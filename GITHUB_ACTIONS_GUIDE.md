# GitHub Actions 检查指南

## 🔍 如何检查 Actions 运行状态

### 方法 1：通过浏览器（推荐）

**访问地址：**
https://github.com/hnsycxm/MyRules/actions

**查看内容：**
1. **左侧面板** - 显示所有工作流
   - Auto Update Rules (主要构建流程)

2. **中间列表** - 最近的运行记录
   - ✅ 绿色对勾 = 成功
   - ❌ 红色叉号 = 失败
   - 🟡 黄色圆圈 = 正在运行
   - ⏸️ 灰色 = 已取消或跳过

3. **点击具体运行** - 查看详细日志
   - 展开每个步骤
   - 查看输出信息
   - 下载生成的文件

---

### 方法 2：使用 GitHub CLI（需要先登录）

#### 步骤 1：登录 GitHub
```powershell
gh auth login
```

按照提示操作：
1. 选择 GitHub.com
2. 选择 HTTPS
3. 复制验证码
4. 在浏览器中完成验证

#### 步骤 2：查看运行列表
```powershell
# 查看最近 5 次运行
gh run list --limit 5

# 查看特定工作流的运行
gh run list --workflow "Auto Update Rules"
```

#### 步骤 3：查看详细状态
```powershell
# 查看最新运行的详细信息
gh run view --log

# 查看运行状态
gh run view --status
```

#### 步骤 4：手动触发工作流
```powershell
# 手动触发一次构建
gh workflow run "auto-update.yml"

# 或者使用完整名称
gh workflow run "Auto Update Rules"
```

---

## 📊 预期的运行结果

### 成功的运行应该包含以下步骤：

1. ✅ **Set up job** - 初始化环境
2. ✅ **Checkout the repository** - 检出代码
3. ✅ **Set up Python** - 配置 Python 环境
4. ✅ **Install dependencies** - 安装依赖
5. ✅ **Built Rules** - 执行构建脚本
   - 下载 Mihomo 工具
   - 处理域名文件
   - 生成 .mrs 文件
6. ✅ **Commit Changes** - 提交更改
7. ✅ **Delete old workflow runs** - 清理旧记录

---

## ⚠️ 常见问题排查

### 问题 1：构建失败 - Python 未找到

**错误信息：**
```
Error: Unable to locate executable file: python
```

**解决方案：**
确保 `requirements.txt` 存在且格式正确

---

### 问题 2：Mihomo 工具下载失败

**可能原因：**
- 网络连接问题
- GitHub 下载限制

**解决方案：**
- 重试运行（通常会自动恢复）
- 考虑使用镜像源

---

### 问题 3：没有检测到更改

**现象：**
```
No changes detected
```

**原因：**
- txt 目录的文件没有变化
- 域名已经排序过去重

**解决方案：**
- 修改 txt 文件中的域名
- 添加新的域名文件

---

## 🎯 定时触发器说明

### 当前配置：
```yaml
schedule:
  - cron: '0 0 * * *'
```

### 运行时间：
- **UTC 时间：** 每天 00:00
- **北京时间：** 每天上午 8:00

### 修改运行时间：

**改为凌晨 2 点（北京）：**
```yaml
schedule:
  - cron: '0 18 * * *'  # UTC 18:00 = 北京 02:00
```

**改为每 6 小时：**
```yaml
schedule:
  - cron: '0 */6 * * *'
```

---

## 📱 通知设置（可选）

### 启用邮件通知：
1. 进入项目 Settings
2. 选择 Notifications
3. 勾选 "Watch" 
4. 设置邮件通知

### 启用 Webhook 通知：
编辑 `config.yaml`：
```yaml
notifications:
  enabled: true
  method: "webhook"
  webhook_url: "https://your-webhook-url.com/notify"
```

---

## 🔗 相关链接

- [GitHub Actions 文档](https://docs.github.com/en/actions)
- [工作流语法参考](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions)
- [Cron 表达式计算器](https://crontab.guru/)

---

**检查时间：** 2026-03-23  
**项目：** hnsycxm/MyRules
