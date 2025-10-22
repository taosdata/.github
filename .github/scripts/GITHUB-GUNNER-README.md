# GitHub Self-Hosted Runner 管理脚本

一个功能完整的 GitHub Self-Hosted Runner 管理工具，支持安装、删除、升级等全生命周期管理。

## 功能特点

### 核心功能

- **安装 (install)**：自动化安装和配置 runner
- **删除 (remove)**：安全删除 runner 及相关配置
- **升级 (upgrade)**：智能升级 runner 版本（带备份回滚）

### 高级特性

- 自动从 GitHub API 获取注册 token
- 完全非交互式操作
- 支持组织级和仓库级 runner
- 支持单个和批量操作
- 智能缓存机制（避免重复下载）
- 完整的备份和回滚机制
- 支持 root 和普通用户
- 详细的日志输出
- 默认禁用自动更新（可选启用）

## 前置要求

### 1. GitHub Personal Access Token (PAT)

**创建步骤：**

1. 访问 https://github.com/settings/tokens
2. 点击 "Generate new token (classic)"
3. 设置 token 名称（如：`runner-manager`）
4. 选择权限范围：
   - **组织级 runner**：勾选 `admin:org`
   - **仓库级 runner**：勾选 `repo`
5. 生成并保存 token

### 2. 系统要求

- Linux 或 macOS 系统
- `curl` 和 `jq` 命令
- `sudo` 权限（普通用户需要）
- 网络连接到 GitHub

### 3. 用户权限

**Root 用户：**
- 可以直接运行
- 不推荐用于生产环境（安全风险）

**普通用户：**
- **推荐用于生产环境**（更安全）
- 需要 `sudo` 权限用于服务管理
- 默认安装目录：`$HOME/actions-runner`

## 快速开始

### 安装 Runner

```bash
# 最简单的安装（组织级）
./manage-github-runner.sh install \
  --owner taosdata \
  --token ghp_xxxxxxxxxxxxxxxxxxxx

# 仓库级 runner
./manage-github-runner.sh install \
  --owner taosdata \
  --repo TDengine \
  --token ghp_xxxxxxxxxxxxxxxxxxxx

# 自定义配置
./manage-github-runner.sh install \
  --owner taosdata \
  --token ghp_xxxxxxxxxxxxxxxxxxxx \
  --name gpu-runner-01 \
  --labels gpu,cuda-12.0,nvidia \
  --install-dir /opt/gpu-runner
```

### 删除 Runner

```bash
# 删除 runner（从 GitHub 注销并删除本地文件）
./manage-github-runner.sh remove \
  --owner taosdata \
  --token ghp_xxxxxxxxxxxxxxxxxxxx \
  --install-dir /opt/runner-01
```

### 升级 Runner

```bash
# 升级到最新版本
./manage-github-runner.sh upgrade \
  --owner taosdata \
  --token ghp_xxxxxxxxxxxxxxxxxxxx \
  --install-dir /opt/runner-01

# 升级到指定版本
./manage-github-runner.sh upgrade \
  --owner taosdata \
  --token ghp_xxxxxxxxxxxxxxxxxxxx \
  --install-dir /opt/runner-01 \
  --target-version 2.328.0
```

## 命令详解

### Install 命令

#### 必需参数

| 参数 | 说明 |
|------|------|
| `--owner OWNER` | GitHub 组织或用户名 |
| `--token TOKEN` | GitHub Personal Access Token |

#### 可选参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--repo REPO` | 空 | 仓库名（留空则为组织级） |
| `--name NAME` | 主机名 | Runner 名称 |
| `--labels LABELS` | 空 | 自定义标签（逗号分隔）<br>系统标签会自动添加 |
| `--install-dir DIR` | `$HOME/actions-runner` | 安装目录 |
| `--group GROUP` | 空 | Runner 组（组织级） |
| `--work-dir DIR` | `_work` | 工作目录 |
| `--version VERSION` | `2.329.0` | Runner 版本 |
| `--os OS` | `linux` | 操作系统（linux/osx） |
| `--arch ARCH` | `x64` | 架构（x64/arm64） |
| `--enable-autoupdate` | 禁用 | 启用 GitHub 自动更新 |

#### 示例

```bash
# 基本安装
./manage-github-runner.sh install \
  --owner taosdata \
  --token ghp_xxx

# 完整配置
./manage-github-runner.sh install \
  --owner taosdata \
  --token ghp_xxx \
  --name prod-runner-01 \
  --labels production,docker,gpu \
  --install-dir /opt/runners/prod-01 \
  --group Production
```

### Remove 命令

#### 必需参数

| 参数 | 说明 |
|------|------|
| `--owner OWNER` | GitHub 组织或用户名 |
| `--token TOKEN` | GitHub Personal Access Token |
| `--install-dir DIR` | Runner 安装目录 |

#### 示例

```bash
# 删除 runner（推荐做法：从 GitHub 注销并删除本地）
./manage-github-runner.sh remove \
  --owner taosdata \
  --token ghp_xxx \
  --install-dir /opt/runner-01

# 批量删除
./manage-github-runner.sh remove \
  --owner taosdata \
  --token ghp_xxx \
  --install-dir "/opt/runner-01;/opt/runner-02;/opt/runner-03"
```

### Upgrade 命令

#### 必需参数

| 参数 | 说明 |
|------|------|
| `--owner OWNER` | GitHub 组织或用户名 |
| `--token TOKEN` | GitHub Personal Access Token |
| `--install-dir DIR` | Runner 安装目录 |

#### 可选参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--target-version VER` | 最新版本 | 目标版本号 |
| `--enable-autoupdate` | 禁用 | 启用 GitHub 自动更新 |

#### 升级特性

- **自动备份**：升级前自动创建时间戳备份
- **智能检测**：自动获取最新版本或指定版本
- **配置保留**：完整保留所有配置文件（包括自动更新设置）
- **失败回滚**：升级失败自动恢复原版本
- **零中断**：等待当前任务完成后升级

#### 升级流程

1. 检查当前版本
2. 停止服务
3. **创建完整备份**
4. 下载新版本（使用缓存）
5. 保留配置文件并解压
6. 重启服务
7. 验证版本

#### 示例

```bash
# 升级到最新版本
./manage-github-runner.sh upgrade \
  --owner taosdata \
  --token ghp_xxx \
  --install-dir /opt/runner-01

# 升级到指定版本
./manage-github-runner.sh upgrade \
  --owner taosdata \
  --token ghp_xxx \
  --install-dir /opt/runner-01 \
  --target-version 2.328.0
```

## 批量操作

### 批量安装

使用分号 (`;`) 分隔多个值：

```bash
./manage-github-runner.sh install \
  --owner taosdata \
  --token ghp_xxx \
  --name "runner-1;runner-2;runner-3" \
  --labels "gpu,cuda;cpu,docker;test" \
  --install-dir "/opt/r1;/opt/r2;/opt/r3"
```

**规则：**
- 参数值数量可以不同
- 如果某参数值较少，最后一个值会被重复使用
- 例如：3个名称 + 1个标签 = 3个 runner，都使用相同标签

### 批量删除

```bash
./manage-github-runner.sh remove \
  --owner taosdata \
  --token ghp_xxx \
  --install-dir "/opt/r1;/opt/r2;/opt/r3"
```

### 批量升级

```bash
./manage-github-runner.sh upgrade \
  --owner taosdata \
  --token ghp_xxx \
  --install-dir "/opt/r1;/opt/r2;/opt/r3"
```

## 高级用法

### 多 Runner 在单台机器

**关键点：**
- 每个 runner **必须有不同的安装目录**
- 每个 runner **必须有不同的名称**
- 服务自动隔离，不会冲突

```bash
# Runner 1
./manage-github-runner.sh install \
  --owner taosdata \
  --token ghp_xxx \
  --name runner-1 \
  --install-dir /opt/runner-1

# Runner 2
./manage-github-runner.sh install \
  --owner taosdata \
  --token ghp_xxx \
  --name runner-2 \
  --install-dir /opt/runner-2

# Runner 3
./manage-github-runner.sh install \
  --owner taosdata \
  --token ghp_xxx \
  --name runner-3 \
  --install-dir /opt/runner-3
```

### 标签使用

**系统自动标签：**
- `self-hosted`
- 操作系统（`Linux`、`macOS` 等）
- 架构（`X64`、`ARM64` 等）

**自定义标签：**
只需指定额外的标签，系统标签会自动添加。

```bash
# 只指定自定义标签
./manage-github-runner.sh install \
  --owner taosdata \
  --token ghp_xxx \
  --labels gpu,cuda-12.0,nvidia

# 实际标签：self-hosted,Linux,X64,gpu,cuda-12.0,nvidia
```

### 使用环境变量

可以用环境变量替代命令行参数：

```bash
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"

./manage-github-runner.sh install \
  --owner taosdata \
  --name my-runner
```

### 下载缓存

脚本会自动缓存下载的 runner 包到 `~/.cache/github-runner/`：

- 避免重复下载
- 加速后续安装
- 支持跨用户共享（复制缓存目录）

```bash
# 从 root 复制缓存到普通用户
mkdir -p /home/username/.cache/github-runner
cp -r /root/.cache/github-runner/* /home/username/.cache/github-runner/
chown -R username:username /home/username/.cache
```

### 自动更新控制

**默认行为：禁用自动更新**

脚本默认禁用 GitHub 的自动更新功能，让你完全控制升级时机：

```bash
# 默认安装（禁用自动更新）
./manage-github-runner.sh install \
  --owner taosdata \
  --token ghp_xxx
```

**启用自动更新：**

如果你希望让 GitHub 自动更新 runner，可以使用 `--enable-autoupdate` 参数：

```bash
# 启用自动更新
./manage-github-runner.sh install \
  --owner taosdata \
  --token ghp_xxx \
  --enable-autoupdate
```

**选择建议：**

| 场景 | 建议 | 原因 |
|------|------|------|
| 生产环境 | 禁用（默认） | 可控的升级时机，避免意外中断 |
| 测试环境 | 启用 | 自动保持最新，减少维护 |
| 多 Runner | 禁用（默认） | 使用本脚本批量升级更可控 |
| 单 Runner | 按需选择 | 根据业务需求决定 |

**手动升级：**

禁用自动更新后，使用 `upgrade` 命令手动升级：

```bash
# 升级到最新版本
./manage-github-runner.sh upgrade \
  --owner taosdata \
  --token ghp_xxx \
  --install-dir /opt/runner-01

# 批量升级
./manage-github-runner.sh upgrade \
  --owner taosdata \
  --token ghp_xxx \
  --install-dir "/opt/r1;/opt/r2;/opt/r3"
```

## Runner 管理

### 查看状态

```bash
sudo /opt/runner-01/svc.sh status
```

### 停止服务

```bash
sudo /opt/runner-01/svc.sh stop
```

### 启动服务

```bash
sudo /opt/runner-01/svc.sh start
```

### 查看日志

```bash
# Runner 诊断日志
cat /opt/runner-01/_diag/*.log

# Systemd 服务日志
sudo journalctl -u actions.runner.*
```

## 安全最佳实践

### Token 管理

1.  **不要硬编码 token**
2.  **不要提交 token 到版本控制**
3.  使用环境变量或密钥管理系统
4.  定期轮换 PAT
5.  使用最小必需权限
6.  为不同环境使用不同的 token

### 用户权限

**生产环境推荐：**

```bash
# 创建专用用户
sudo useradd -m -s /bin/bash github-runner
sudo usermod -aG sudo github-runner

# 配置 sudo 免密（仅用于服务管理）
echo "github-runner ALL=(ALL) NOPASSWD: /bin/systemctl" | sudo tee /etc/sudoers.d/github-runner

# 切换到该用户
sudo su - github-runner

# 安装 runner
./manage-github-runner.sh install \
  --owner taosdata \
  --token ghp_xxx
```

## 实用场景

### 场景 1：生产环境多 Runner 部署

```bash
#!/bin/bash
# deploy-production-runners.sh

export GITHUB_OWNER="taosdata"
export GITHUB_TOKEN="ghp_xxx"

./manage-github-runner.sh install \
  --name "prod-runner-1;prod-runner-2;prod-runner-3" \
  --labels "production,docker" \
  --install-dir "/opt/runner-1;/opt/runner-2;/opt/runner-3"
```

### 场景 2：滚动升级生产 Runners

```bash
#!/bin/bash
# rolling-upgrade.sh

RUNNERS=("/opt/runner-1" "/opt/runner-2" "/opt/runner-3")

for runner in "${RUNNERS[@]}"; do
  echo "Upgrading $runner..."
  ./manage-github-runner.sh upgrade \
    --owner taosdata \
    --token ghp_xxx \
    --install-dir "$runner"
  
  echo "Waiting 30s before next upgrade..."
  sleep 30
done
```

### 场景 3：安装特定版本

```bash
# 安装旧版本用于测试
./manage-github-runner.sh install \
  --owner taosdata \
  --token ghp_xxx \
  --name test-runner \
  --install-dir /tmp/test-runner \
  --version 2.320.0

# 测试升级功能
./manage-github-runner.sh upgrade \
  --owner taosdata \
  --token ghp_xxx \
  --install-dir /tmp/test-runner

# 清理
./manage-github-runner.sh remove \
  --install-dir /tmp/test-runner
```

## 故障排查

### 常见问题

#### Q1: 401 Unauthorized

**原因：** Token 无效或权限不足

**解决：**
1. 检查 token 是否正确
2. 确认 token 有正确权限（`admin:org` 或 `repo`）
3. 重新生成 token

#### Q2: Runner 已存在

**原因：** 同名 runner 已在 GitHub 注册

**解决：**
```bash
# 先删除旧 runner
./manage-github-runner.sh remove \
  --owner taosdata \
  --token ghp_xxx \
  --install-dir /path/to/runner

# 重新安装
./manage-github-runner.sh install ...
```

#### Q3: 安装目录已存在

**原因：** 目录已有内容

**解决：**
1. 检查是否有正在运行的 runner
2. 删除目录或使用不同路径
3. 或先执行 remove 命令

#### Q4: Sudo 权限问题

**原因：** 普通用户没有 sudo 权限

**解决：**
```bash
# 添加用户到 sudo 组
sudo usermod -aG sudo username

# 或配置 sudoers
echo "username ALL=(ALL) NOPASSWD: /path/to/svc.sh" | sudo tee /etc/sudoers.d/runner
```

#### Q5: 升级后服务无法启动

**原因：** 升级过程出错

**解决：**
```bash
# 查看备份
ls -la /path/to/runner.backup.*

# 手动回滚
sudo systemctl stop actions.runner.*.service
rm -rf /path/to/runner
mv /path/to/runner.backup.TIMESTAMP /path/to/runner
sudo systemctl start actions.runner.*.service
```

### 日志位置

```bash
# Runner 诊断日志
~/.cache/github-runner/
/opt/runner-01/_diag/

# 脚本日志
# 脚本输出的所有 [INFO]、[WARNING]、[ERROR] 消息

# 系统服务日志
sudo journalctl -u actions.runner.* -f
```

### 检查清单

运行前检查：
- [ ] GitHub token 有效且权限正确
- [ ] 网络可以访问 GitHub
- [ ] 有足够的磁盘空间
- [ ] 用户有必要的权限
- [ ] 安装目录不存在或为空

## 参考文档

- [GitHub Actions 官方文档](https://docs.github.com/en/actions)
- [Self-hosted Runner 管理](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Runner Releases](https://github.com/actions/runner/releases)
- [GitHub REST API](https://docs.github.com/en/rest)