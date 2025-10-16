# Deploy Superset Action

这个 GitHub Action 用于通过 Docker 部署 Apache Superset 服务，支持自定义数据库和 Redis 配置。

## 功能特性

- ✅ 支持 PostgreSQL 和 MySQL 数据库
- ✅ 支持 Redis 缓存和 Celery 配置
- ✅ 自动初始化数据库和管理员用户
- ✅ 可配置的 Superset 版本
- ✅ 健康检查和错误处理
- ✅ 支持自定义配置

## 使用方法

```yaml
- name: Deploy Superset
  uses: ./.github/actions/deploy-superset
  with:
    # 必需参数
    superset-secret-key: ${{ secrets.SUPERSET_SECRET_KEY }}
    database-type: 'postgresql'
    database-host: ${{ secrets.DB_HOST }}
    database-name: ${{ secrets.DB_NAME }}
    database-user: ${{ secrets.DB_USER }}
    database-password: ${{ secrets.DB_PASSWORD }}
    redis-host: ${{ secrets.REDIS_HOST }}
    admin-password: ${{ secrets.SUPERSET_ADMIN_PASSWORD }}
```

## 输入参数

### 必需参数

| 参数 | 描述 | 示例 |
|------|------|------|
| `superset-secret-key` | Superset 密钥 | `your-secret-key` |
| `database-type` | 数据库类型 | `postgresql` 或 `mysql` |
| `database-host` | 数据库主机 | `postgres.example.com` |
| `database-name` | 数据库名称 | `superset` |
| `database-user` | 数据库用户 | `superset_user` |
| `database-password` | 数据库密码 | `password123` |
| `redis-host` | Redis 主机 | `redis.example.com` |
| `admin-password` | 管理员密码 | `admin123` |

### 可选参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `superset-version` | Superset 版本 | `latest` |
| `superset-port` | 服务端口 | `8088` |
| `database-port` | 数据库端口 | `5432` |
| `redis-port` | Redis 端口 | `6379` |
| `redis-password` | Redis 密码 | `''` |
| `redis-db` | Redis 数据库 | `1` |
| `container-name` | 容器名称 | `superset` |
| `network-name` | Docker 网络 | `superset-network` |
| `admin-username` | 管理员用户名 | `admin` |
| `admin-email` | 管理员邮箱 | `admin@superset.com` |

## 输出

| 输出 | 描述 |
|------|------|
| `superset-url` | Superset 访问地址 |
| `container-id` | 容器 ID |

