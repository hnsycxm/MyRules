# 贡献指南

感谢您对 MyRules 项目的关注！我们欢迎任何形式的贡献。

## 如何贡献

### 报告问题

如果您发现了 bug 或有功能建议，请：

1. 检查 [Issues](../../issues) 确认问题是否已被报告
2. 如果没有，创建新的 Issue，包括：
   - 清晰的标题
   - 详细的问题描述
   - 复现步骤（如果是 bug）
   - 预期行为和实际行为
   - 环境信息（操作系统、Python 版本等）

### 提交代码

#### 开发环境设置

1. Fork 本仓库
2. 克隆您的 fork：
   ```bash
   git clone https://github.com/your-username/MyRules.git
   cd MyRules
   ```

3. 安装依赖：
   ```bash
   pip install pyyaml
   ```

#### 代码规范

- **Python 代码**：遵循 PEP 8 规范
- **Bash 脚本**：使用 ShellCheck 检查
- **注释**：关键逻辑必须添加注释
- **变量命名**：使用有意义的变量名

#### 提交流程

1. 创建新分支：
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. 进行修改并测试：
   ```bash
   # 本地测试构建脚本
   bash script/build-combined-rules.sh
   ```

3. 提交更改：
   ```bash
   git add .
   git commit -m "feat: 添加功能描述"
   ```

   提交信息格式：
   - `feat:` 新功能
   - `fix:` 修复 bug
   - `docs:` 文档更新
   - `style:` 代码格式调整
   - `refactor:` 代码重构
   - `test:` 测试相关
   - `chore:` 构建/工具相关

4. 推送到您的 fork：
   ```bash
   git push origin feature/your-feature-name
   ```

5. 创建 Pull Request

#### Pull Request 要求

- 清晰描述更改内容
- 引用相关的 Issue（如果有）
- 确保所有测试通过
- 更新相关文档

### 测试

在提交 PR 前，请确保：

1. 本地测试构建脚本正常运行
2. 生成的 .mrs 文件可用
3. 没有引入新的 bug
4. 代码符合项目规范

### 文档贡献

- 如果您发现文档有错误或不清晰的地方，欢迎改进
- 新功能需要添加相应的文档说明
- 保持文档的简洁和准确

## 行为准则

- 尊重所有贡献者
- 接受建设性的批评
- 关注对社区最有利的事情
- 对不同观点保持同理心

## 许可证

通过贡献代码，您同意您的贡献将根据项目的许可证进行授权。

## 联系方式

如有疑问，请通过以下方式联系：

- 提交 Issue
- 在 Discussion 中讨论
- 联系项目维护者

---

再次感谢您的贡献！
