#!/bin/bash
# OpenTSDB 安装脚本 (Shell版本)

set -e  # 遇到错误立即退出

# 配置参数
OPENTSDB_VERSION="${1:-2.4.1}"
PROTOBUF_VERSION="${2:-2.5.0}"
HBASE_HOME="${3:-/opt/hbase}"
ZK_QUORUM="${3:-localhost}"
# INSTALL_DIR="/usr/share/opentsdb"
OPENTSDB_HOME="/usr/share/opentsdb"
TSDB_PORT=4242
TSDB_LOG="/var/log/opentsdb.log"
# RPM_URL="https://github.com/OpenTSDB/opentsdb/releases/download/v${VERSION}/opentsdb-2.4.1-1-20210902183110-root.noarch.rpm"

get_db_download_url() {
    # 基于不同版本号获取 OpenTSDB 下载地址
    if [ "$OPENTSDB_VERSION" == "2.4.1" ]; then
        RPM_URL="https://github.com/OpenTSDB/opentsdb/releases/download/v2.4.1/opentsdb-2.4.1-1-20210902183110-root.noarch.rpm"
    elif [ "$OPENTSDB_VERSION" == "2.4.0" ]; then
        RPM_URL="https://github.com/OpenTSDB/opentsdb/releases/download/v2.4.0/opentsdb-2.4.0.noarch.rpm"
    fi
}

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

install_dependencies(){
    # 安装基础依赖
    echo "[INFO][1/7] 安装系统依赖..."
    case "$OS_ID" in
        ubuntu|debian)
            apt-get update
            # if command -v python3 &> /dev/null; then
            #     apt-get install -y python3
            #     ln -sf /usr/bin/python3 /usr/bin/python
            # fi
            apt-get install -y git wget curl make autoconf automake libtool pkg-config build-essential
            ;;
        centos|rhel)
            # if command -v python3 &> /dev/null; then
            #     yum install -y python3
            #     ln -sf /usr/bin/python3 /usr/bin/python
            # fi
            yum install -y git wget curl make autoconf automake libtool pkgconfig gcc-c++
            ;;
        opensuse-leap|sles|suse)
            # if command -v python3 &> /dev/null; then
            #     zypper --non-interactive install -y python3
            #     ln -sf /usr/bin/python3 /usr/bin/python
            # fi
            zypper --non-interactive install -y \
            git wget curl make autoconf automake libtool pkg-config \
            gcc-c++ python3 tar which gzip
            ;;
        *)
            echo "[ERROR] 不支持的系统：$OS_ID"
            exit 1
            ;;
    esac

    # 安装Protobuf
    echo "[INFO][2/7] 安装Protobuf $PROTOBUF_VERSION..."
    cd /tmp
    wget https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUF_VERSION}/protobuf-${PROTOBUF_VERSION}.tar.gz
    tar -xzf protobuf-${PROTOBUF_VERSION}.tar.gz
    cd protobuf-${PROTOBUF_VERSION}
    ./configure
    make -j$(nproc)
    make install
    ldconfig
}

uninstall_opentsdb(){
    # 卸载 OpenTSDB
    echo "[INFO][3/7] 安装系统依赖..."
    rpm -e opentsdb || true
    # 删除日志、临时缓存、配置文件等（慎用）
    # rm -rf /usr/share/opentsdb
    rm -rf $OPENTSDB_HOME
    rm -rf /tmp/tsdb_cache
    rm -f $TSDB_LOG
}

install_opentsdb(){
    # ========== 下载并安装 RPM ==========
    echo "[INFO][4/7] 下载 OpenTSDB RPM..."
    get_db_download_url
    echo curl -L -o "/tmp/opentsdb-${OPENTSDB_VERSION}.rpm" "$RPM_URL"
    curl -L -o "/tmp/opentsdb-${OPENTSDB_VERSION}.rpm" "$RPM_URL"
    # wget -q --show-progress "$RPM_URL" -O "opentsdb-${OPENTSDB_VERSION}.rpm"

    echo "[INFO][5/7] 安装 OpenTSDB RPM..."
    yum localinstall -y "/tmp/opentsdb-${OPENTSDB_VERSION}.rpm"

    # ========== 创建 TSDB 表 ==========
    echo "[INFO][6/7] 创建 HBase 表..."
    COMPRESSION=NONE HBASE_HOME=$HBASE_HOME $OPENTSDB_HOME/tools/create_table.sh
    if [ $? -ne 0 ]; then
        echo "[ERROR] 创建 HBase 表失败，请检查 HBase 配置和连接"
        exit 1
    fi

    # ========== 启动 OpenTSDB ==========
    echo "[INFO][7/7] 启动 OpenTSDB 服务..."
    chmod a+x /usr/share/opentsdb/bin/tsdb
    mkdir -p /tmp/tsdb_cache

    nohup /usr/share/opentsdb/bin/tsdb tsd \
        --port=$TSDB_PORT \
        --staticroot=/usr/share/opentsdb/static \
        --cachedir=/tmp/tsdb_cache \
        --zkquorum=$ZK_QUORUM > "$TSDB_LOG" 2>&1 &
    
    echo "[INFO] 安装完成！"
    echo "[INFO] 访问界面：http://服务器IP:4242"
}


### 主流程
main() {
    check_privilege
    detect_os
    install_dependencies
    uninstall_opentsdb
    install_opentsdb
}

main "$@"