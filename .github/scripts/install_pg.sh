#!/bin/bash

set -e
# set -x

# 版本号可以通过命令行参数传入，默认版本为 15
# Usage: ./install_pg.sh <version>

# PostgreSQL 版本要求
# | PostgreSQL 版本 | Ubuntu 最低版本  | CentOS/RHEL 最低版本  | openSUSE/SLES 最低版本  |
# | ------------- | ------------ | ----------------- | ------------------- |
# | 16            | Ubuntu 20.04 | CentOS 8 / RHEL 8 | openSUSE Leap 15.4+ |
# | 15            | Ubuntu 18.04 | CentOS 7          | openSUSE Leap 15.2+ |
# | 14            | Ubuntu 16.04 | CentOS 7          | openSUSE Leap 15+   |
# | 13            | Ubuntu 16.04 | CentOS 7          | openSUSE Leap 15+   |
# | 12            | Ubuntu 14.04 | CentOS 7          | openSUSE Leap 15+   |

# | PostgreSQL 版本 | 最低 glibc 要求 | 是否依赖 systemd | 最低 Linux 内核建议 |
# | ------------- | ----------- | ------------ | ------------- |
# | 16            | 2.28+       | 是            | 4.18+         |
# | 15            | 2.17+       | 是            | 3.10+         |
# | 14            | 2.17+       | 是            | 3.10+         |
# | 13            | 2.17+       | 是（可替代）    | 3.10+         |
# | 12            | 2.12+       | 否            | 2.6.32+       |

# 用户名: postgres
# 密码: MyNewPassw0rd!
# 连接命令: psql -U postgres -h localhost
# 或: PGPASSWORD='MyNewPassw0rd!' psql -U postgres -h localhost -d postgres


PG_VERSION="${1:-15}"
INSTALL_DIR="/opt/kafka"
NEW_PASSWORD="MyNewPassw0rd!"


error_exit() {
    echo "错误: $1" >&2
    exit 1
}

# 用户权限级别校验
check_privilege(){
    if [ "$(id -u)" -ne 0 ]; then
        echo "[ERROR] 需要 root 权限的用户运行脚本"
        exit 1
fi
}

# 判断系统
function detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
    else
        echo "[ERROR] 无法检测操作系统"
        exit 1
    fi
}

function compare_versions() {
    # 用于比较版本号，返回 0 表示 v1 >= v2
    # 用法：compare_versions "$v1" "$v2"
    [ "$1" = "$2" ] && return 0
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

function check_requirements() {
    echo "Checking system requirements..."

    # 当前系统的 glibc 和 kernel 版本
    glibc_ver=$(ldd --version | head -n1 | awk '{print $NF}')
    kernel_ver=$(uname -r | cut -d- -f1)

    # 根据 PostgreSQL 版本要求的最小 glibc 和 kernel 版本
    case "$PG_VERSION" in
        16)
            required_glibc="2.28"
            required_kernel="4.18"
            ;;
        15|14|13)
            required_glibc="2.17"
            required_kernel="3.10"
            ;;
        12)
            required_glibc="2.12"
            required_kernel="2.6.32"
            ;;
        *)
            echo "[ERROR] Unknown or unsupported PostgreSQL version: $PG_VERSION"
            exit 1
            ;;
    esac

    echo "[INFO] Detected glibc version: $glibc_ver (required ≥ $required_glibc)"
    echo "[INFO] Detected kernel version: $kernel_ver (required ≥ $required_kernel)"

    if compare_versions "$glibc_ver" "$required_glibc"; then
        echo "[INFO] glibc version OK"
    else
        echo "[ERROR] glibc version too low: $glibc_ver < $required_glibc"
        exit 1
    fi

    if compare_versions "$kernel_ver" "$required_kernel"; then
        echo "[INFO] Kernel version OK"
    else
        echo "[WARN] Kernel version too low: $kernel_ver < $required_kernel"
    fi
}

uninstall_pg() {
    echo "[INFO] 检查并删除系统中已有的 PostgreSQL..."

    if command -v psql >/dev/null 2>&1; then
        echo "[INFO] 检测到已有 PostgreSQL 安装，执行卸载..."
        pg_major_version=$(psql --version | awk '{print $3}' | cut -d. -f1)
        echo "当前 PostgreSQL 版本为：$pg_major_version"

        case "$OS_ID" in
            ubuntu|debian)
                systemctl stop postgresql || true
                apt-get remove --purge -y postgresql* libpq-dev postgresql-client*
                apt-get autoremove -y
                ;;

            centos|rhel|rocky|almalinux)
                systemctl stop postgresql-$pg_major_version || true
                yum remove -y postgresql* || true
                ;;

            sles|opensuse-leap|opensuse)
                systemctl stop postgresql || true
                zypper remove -y postgresql* || true
                ;;

            *)
                echo "[WARNING] 未知操作系统 $os_id，无法自动卸载 PostgreSQL。请手动处理。"
                ;;
        esac

        # 可选：清理残留文件夹
        rm -rf /var/lib/pgsql /var/lib/postgresql /etc/postgresql /etc/pgsql /usr/pgsql* /usr/lib/postgresql /opt/pgsql
        echo "[INFO] PostgreSQL 卸载完成。"
    else
        echo "[INFO] 系统中未检测到 PostgreSQL，无需卸载。"
    fi
}

function install_postgresql_ubuntu() {
    echo "[INFO] 正在为 Ubuntu 安装 PostgreSQL $PG_VERSION"

    apt-get update
    apt-get install -y wget gnupg lsb-release

    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | \
        tee /etc/apt/sources.list.d/pgdg.list

    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
        gpg --dearmor | tee /usr/share/keyrings/postgresql.gpg > /dev/null

    apt-get update
    apt-get install -y "postgresql-$PG_VERSION" "postgresql-client-$PG_VERSION"
}

function install_postgresql_centos() {
    echo "[INFO] 正在为 CentOS 安装 PostgreSQL $PG_VERSION"

    if ! rpm -q pgdg-redhat-repo &>/dev/null; then
        yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-$(rpm -E %{rhel})-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    else
        echo "[INFO] pgdg-redhat-repo 已安装, 跳过下载步骤"
    fi

    yum -y module disable postgresql || true
    yum install -y "postgresql$PG_VERSION-server" "postgresql$PG_VERSION"

    /usr/pgsql-${PG_VERSION}/bin/postgresql-${PG_VERSION}-setup initdb
    systemctl enable "postgresql-$PG_VERSION"
    systemctl start "postgresql-$PG_VERSION"
}

function install_postgresql_suse() {
    echo "[INFO] 正在为 openSUSE 安装 PostgreSQL $PG_VERSION"

    zypper refresh
    zypper install -y "postgresql$PG_VERSION-server"

    systemctl enable "postgresql"
    systemctl start "postgresql"
}

function install_pg() {
    case "$OS_ID" in
        ubuntu)
            install_postgresql_ubuntu
            ;;
        centos|rhel)
            install_postgresql_centos
            ;;
        opensuse*|sles)
            install_postgresql_suse
            ;;
        *)
            echo "[ERROR] 当前系统 $OS_ID 不受支持"
            exit 1
            ;;
    esac

    echo "[INFO] PostgreSQL $PG_VERSION 安装完成！"
}

alter_postgres_password() {
    # 检查 PostgreSQL 是否安装
    if ! command -v psql &> /dev/null; then
        echo "PostgreSQL 未安装，请先安装 PostgreSQL"
        exit 1
    fi

    # # 启动 PostgreSQL 服务
    # echo "检查 PostgreSQL 服务状态..."
    # if ! systemctl is-active --quiet postgresql; then
    #     echo "启动 PostgreSQL 服务..."
    #     systemctl start postgresql || echo "无法启动 PostgreSQL 服务" | exit 1
    #     systemctl enable postgresql 2>/dev/null
    # fi

    # 查找 pg_hba.conf 文件
    echo "查找 pg_hba.conf 配置文件..."
    PG_HBA_CONF=$(sudo -u postgres psql -t -c "SHOW hba_file;" 2>/dev/null | tr -d ' ')

    if [ -z "$PG_HBA_CONF" ] || [ ! -f "$PG_HBA_CONF" ]; then
        # 尝试常见路径
        COMMON_PATHS=(
            "/var/lib/pgsql/data/pg_hba.conf"
            "/var/lib/postgresql/*/main/pg_hba.conf"
            "/etc/postgresql/*/main/pg_hba.conf"
        )
        
        for path in "${COMMON_PATHS[@]}"; do
            if [ -f $path ]; then
                PG_HBA_CONF=$path
                break
            fi
        done
    fi

    if [ -z "$PG_HBA_CONF" ] || [ ! -f "$PG_HBA_CONF" ]; then
        error_exit "无法找到 pg_hba.conf 文件"
    fi

    echo "找到配置文件: $PG_HBA_CONF"

    # 备份原始配置文件
    BACKUP_FILE="${PG_HBA_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$PG_HBA_CONF" "$BACKUP_FILE"
    echo "已创建备份: $BACKUP_FILE"

    # 修改认证方式为 md5
    echo "修改认证方式为密码认证..."
    sed -i 's/^local\s\+all\s\+all\s\+peer$/local   all             all                                     md5/' "$PG_HBA_CONF"
    sed -i 's/^local\s\+all\s\+all\s\+ident$/local   all             all                                     md5/' "$PG_HBA_CONF"
    sed -i 's/^local\s\+all\s\+all\s\+trust$/local   all             all                                     md5/' "$PG_HBA_CONF"

    # 修改密码
    echo "设置 postgres 用户密码..."
    sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$NEW_PASSWORD';" 2>/dev/null || \
    echo "警告: 无法通过 psql 设置密码，可能需要其他方式"

    # 重启 PostgreSQL 使配置生效
    echo "重启 PostgreSQL 服务..."
    case "$OS_ID" in
        ubuntu)
            systemctl restart postgresql || error_exit "无法重启 PostgreSQL 服务"
            ;;
        centos|rhel)
            systemctl restart "postgresql-$PG_VERSION" || error_exit "无法重启 PostgreSQL 服务"
            ;;
        opensuse*|sles)
            systemctl restart postgresql || error_exit "无法重启 PostgreSQL 服务"
            ;;
        *)
            echo "[ERROR] 当前系统 $OS_ID 不受支持"
            exit 1
            ;;
    esac

    # 验证密码是否生效
    echo "验证密码设置..."
    sleep 2  # 等待服务完全启动

    if PGPASSWORD="$NEW_PASSWORD" psql -U postgres -h localhost -c "\q" 2>/dev/null; then
        echo "密码设置成功！"
        echo "认证配置已更新"
    else
        echo "密码验证失败，但密码可能已设置"
        echo "请尝试手动登录: psql -U postgres -h localhost"
    fi

    echo ""
    echo "=== 设置完成 ==="
    echo "用户名: postgres"
    echo "密码: $NEW_PASSWORD"
    echo "连接命令: psql -U postgres -h localhost"
    echo "或: PGPASSWORD='$NEW_PASSWORD' psql -U postgres -h localhost -d postgres"
}

main() {
    check_privilege
    detect_os
    uninstall_pg
    check_requirements
    install_pg
    alter_postgres_password
}

main "$@"
