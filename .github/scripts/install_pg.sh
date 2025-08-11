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

PG_VERSION="${1:-15}"
INSTALL_DIR="/opt/kafka"


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

main() {
    check_privilege
    detect_os
    uninstall_pg
    check_requirements
    install_pg
}

main "$@"
