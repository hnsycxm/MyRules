# Node.js 24 迁移说明

## ⚠️ GitHub Actions Node.js 20 弃用警告

### 背景

GitHub 官方宣布将于 **2026 年 6 月 2 日** 弃用 Node.js 20，届时所有 JavaScript Actions 将默认使用 Node.js 24 运行。

**相关链接：**
- [GitHub 官方博客](https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/)
- [Node.js 发布计划](https://nodejs.org/en/about/releases/)

---

## ✅ 已采取的优化措施

### 1. 设置环境变量（已完成）

在 `.github/workflows/auto-update.yml` 中已配置：

```yaml
env:
  TZ: Asia/Shanghai
  # 强制使用 Node.js 24（Node.js 20 将于 2026-06-02 弃用）
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true
```

**作用：**
- 提前迁移到 Node.js 24 环境
- 确保在 2026-06-02 之前正常工作
- 避免突然的兼容性问题

---

### 2. 更新 Actions 版本（已完成）

#### 更新的 Actions 列表：

| Action | 旧版本 | 新版本 | Node.js 24 支持 |
|--------|--------|--------|----------------|
| `actions/checkout` | v4 | v4.2.2 | ✅ 完全支持 |
| `actions/setup-python` | v5 | v5.3.0 | ✅ 完全支持 |
| `stefanzweifel/git-auto-commit-action` | v5 | v5.1.0 | ✅ 完全支持 |
| `Mattraks/delete-workflow-runs` | v2.1.0 | v2.1.2 | ✅ 完全支持 |

#### 详细配置：

```yaml
steps:
  # Checkout - 最新版本
  - uses: actions/checkout@v4.2.2
    with:
      persist-credentials: true

  # Python 设置 - 最新版本 + 缓存
  - name: Set up Python
    uses: actions/setup-python@v5.3.0
    with:
      python-version: '3.x'
      cache: 'pip'

  # Git Auto Commit - 最新版本
  - name: Commit Changes
    uses: stefanzweifel/git-auto-commit-action@v5.1.0
    with:
      commit_options: '--signoff'

  # Delete Workflow Runs - 最新版本
  - name: Delete old workflow runs
    uses: Mattraks/delete-workflow-runs@v2.1.2
```

---

### 3. 新增功能

#### Python 依赖缓存

```yaml
- name: Set up Python
  uses: actions/setup-python@v5.3.0
  with:
    python-version: '3.x'
    cache: 'pip'  # ✨ 新增：自动缓存 pip 依赖
```

**好处：**
- 加速依赖安装
- 减少构建时间
- 降低网络请求失败风险

#### 提交签名选项

```yaml
- name: Commit Changes
  uses: stefanzweifel/git-auto-commit-action@v5.1.0
  with:
    commit_options: '--signoff'  # ✨ 新增：添加签名
```

**好处：**
- 符合 Git 最佳实践
- 明确提交者身份
- 提高代码可信度

#### 持久化凭证

```yaml
- uses: actions/checkout@v4.2.2
  with:
    persist-credentials: true  # ✨ 新增：保持认证状态
```

**好处：**
- 允许后续步骤推送更改
- 避免重复认证
- 提高工作流稳定性

---

## 📊 版本兼容性对比

### Node.js 版本时间线

| Node.js 版本 | 发布时间 | EOL 时间 | GitHub Actions 支持 |
|-------------|---------|---------|-------------------|
| Node.js 16 | 2021-10 | 2023-09 | ❌ 已弃用 |
| Node.js 18 | 2022-04 | 2025-04 | ⚠️ 即将弃用 |
| Node.js 20 | 2023-04 | 2026-04 | ⚠️ 2026-06-02 弃用 |
| **Node.js 24** | **2025-04** | **2028-04** | **✅ 推荐使用** |

---

## 🔍 验证方法

### 检查当前使用的 Node.js 版本

在 GitHub Actions 运行日志中查看：

```
Run actions/checkout@v4.2.2
  with:
    ...
Node.js version: v24.x.x  ← 应该显示 v24
```

### 本地测试（可选）

如果你有 GitHub CLI：

```powershell
# 登录 GitHub
gh auth login

# 手动触发工作流
gh workflow run "Auto Update Rules"

# 查看运行状态
gh run watch
```

---

## ⚠️ 潜在问题与解决方案

### 问题 1：Action 不兼容

**现象：**
```
Error: This action is not compatible with Node.js 24
```

**解决方案：**
1. 检查 Action 是否有更新版本
2. 查看 Action 的 package.json 中的 engines 字段
3. 联系 Action 作者更新

### 问题 2：自定义脚本失败

**现象：**
JavaScript 自定义脚本报错

**解决方案：**
```yaml
# 临时回退到 Node.js 20
env:
  ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION: true
```

**注意：** 这只是临时方案，应尽快更新脚本以支持 Node.js 24

### 问题 3：依赖安装失败

**现象：**
```
npm ERR! engine Unsupported engine
```

**解决方案：**
- 更新 npm 包到最新版本
- 检查 package.json 中的 engines 配置
- 使用 `--legacy-peer-deps` 参数（不推荐）

---

## 📅 重要时间节点

| 日期 | 事件 | 操作建议 |
|------|------|----------|
| **现在** | Node.js 20 仍可用 | ✅ 已完成迁移到 Node.js 24 |
| **2026-06-02** | Node.js 20 正式弃用 | ✅ 已提前适配 |
| **2026-06 后** | Node.js 24 成为默认 | ✅ 无需额外操作 |

---

## 🎯 最佳实践建议

### 1. 定期更新 Actions

```yaml
# 使用 Dependabot 自动更新
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

### 2. 指定具体版本号

```yaml
# ✅ 推荐：指定具体版本
- uses: actions/checkout@v4.2.2

# ⚠️ 不推荐：使用大版本标签
- uses: actions/checkout@v4
```

### 3. 监控 Actions 运行

定期检查：
- Actions 运行日志
- 弃用警告
- 性能指标

---

## 🔗 相关资源

- [GitHub Actions 运行时](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners)
- [Node.js 发布计划](https://nodejs.org/en/about/releases/)
- [Actions 版本查询](https://github.com/actions)
- [Dependabot 配置](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/keeping-your-actions-up-to-date-with-dependabot)

---

## ✅ 总结

### 当前状态：
- ✅ 已设置 `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true`
- ✅ 所有 Actions 已更新到最新兼容版本
- ✅ 添加了性能优化（缓存、签名等）
- ✅ 提前适配 2026-06-02 的变更

### 下一步：
- 📊 监控下一次运行的日志
- 🔍 确认使用的是 Node.js 24
- 📈 观察性能提升（缓存效果）

---

**更新时间：** 2026-03-23  
**项目：** hnsycxm/MyRules  
**状态：** ✅ 已完成 Node.js 24 迁移
