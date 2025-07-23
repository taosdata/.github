#!/bin/bash

set -e
# set -x
# 版本号和部署模式可以通过命令行参数传入，默认版本为 3.9.1，默认部署模式为 kraft
# Usage: ./install_kafka.sh <version> <deploy_mode> <server_ip> <donwload_url>
# deploy_mode: kraft 或 zookeeper
# NOTE: Kraft 模式从 Kafka 2.8.0 开始引入

KAFKA_VERSION="${1:-3.9.1}"
DEPLOY_MODE="${2:-kraft}"  # kraft 或 zookeeper
SERVER_IP="${3:-localhost}" # Kafka 广播的 IP 地址，默认为 localhost
DOWNLOAD_URL="${4:-undefined}" # 可选的下载 URL，如果未提供则使用默认镜像
INSTALL_DIR="/opt/kafka"
KAFKA_USER="kafka"
USE_KRAFT=""

# 根据版本提取主版本号
get_major_version() {
  echo "$1" | cut -d. -f1
}
get_minor_version() {
  echo "$1" | cut -d. -f2
}

# 
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

is_domestic() {
    # Test connectivity to a domestic server (e.g., Tsinghua mirror)
    ping -c 1 mirrors.tuna.tsinghua.edu.cn &> /dev/null
    if [ $? -eq 0 ]; then
        return 0  # Domestic
    else
        return 1  # International
    fi
}

# 安装对应版本的 JDK
# | Kafka 版本            | 最低支持 JDK | 推荐 JDK         | 支持的最大 JDK 版本      |
# | -------------------- | ----------- | --------------- | ---------------------- |
# | Kafka 2.0.x – 2.3.x  | JDK 8       | JDK 8           | JDK 8                  |
# | Kafka 2.4.x – 2.7.x  | JDK 8       | JDK 8 / JDK 11  | JDK 11（不支持 JDK 17）  |
# | Kafka 2.8.x          | JDK 8       | JDK 8 / JDK 11  | JDK 11（部分支持 JDK 17）|
# | Kafka 3.0.x – 3.2.x  | JDK 8       | JDK 11          | JDK 17（实验性支持）      |
# | Kafka 3.3.x+         | JDK 11      | JDK 11 / JDK 17 | JDK 17（稳定）          |
# | Kafka 3.5.x+         | JDK 11      | JDK 17          | JDK 17                 |
# | Kafka 3.6.x          | JDK 11      | JDK 17          | JDK 21（部分兼容）       |
install_jdk() {
    local major=$(get_major_version "$KAFKA_VERSION")
    local minor=$(get_minor_version "$KAFKA_VERSION")
    local jdk_ver=""
    
    if [ "$major" -le 2 ] && [ "$minor" -le 7 ]; then    # Kafka 2.0.x – 2.7.x
        jdk_ver="8"
    elif [ "$major" -eq 2 ] && [ "$minor" -ge 8 ]; then  # Kafka 2.8.x
        jdk_ver="11"
    elif [ "$major" -eq 3 ] && [ "$minor" -le 3 ]; then  # Kafka 3.0.x – 3.3.x
        jdk_ver="11"
    elif [ "$major" -eq 3 ] && [ "$minor" -ge 3 ]; then  # Kafka 3.4.x 及以上
        # jdk_ver="17"
        jdk_ver="11"  # 因为java17不支持老版本系统，比如centos7，所以这里默认使用 JDK 11
    else
        echo "[INFO] 无法判断 Kafka $KAFKA_VERSION 所需 JDK 版本，默认使用 JDK 11"
        jdk_ver="11"
    fi

    echo "[INFO] Kafka $KAFKA_VERSION → 安装 JDK $jdk_ver"
    # 判断是否已安装 Java
    if command -v java >/dev/null 2>&1 || command -v javac >/dev/null 2>&1; then
        echo "[INFO] 检测到已安装 Java，准备卸载旧版本..."

        case "$OS_ID" in
            ubuntu|debian)
                apt-get remove --purge -y openjdk-* default-jdk default-jre || true
                apt-get autoremove -y
                ;;
            centos|rhel)
                yum remove -y java-* || true
                ;;
            opensuse-leap|sles|suse)
                zypper --non-interactive remove java-* || true
                ;;
            *)
                echo "[ERROR] 不支持的系统：$OS_ID"
                exit 1
                ;;
        esac
    else
        echo "[INFO] 当前未检测到已安装 Java，跳过卸载"
    fi

    echo "[INFO] 安装 JDK $jdk_ver..."
    case "$OS_ID" in
        ubuntu|debian)
            apt-get update -y
            apt-get install -y openjdk-${jdk_ver}-jdk
            ;;
        centos|rhel)
            yum install -y java-${jdk_ver}-openjdk java-${jdk_ver}-openjdk-devel
            ;;
        opensuse-leap|sles|suse)
            zypper install -y java-${jdk_ver}-openjdk java-${jdk_ver}-openjdk-devel
            ;;
        *)
            echo "[ERROR] 不支持的系统：$OS_ID"
            exit 1
            ;;
    esac

    # 获取 Java path
    JAVA_PATH=$(dirname $(dirname $(readlink -f $(which javac))))

    # 检查 .bashrc 中是否已定义 JAVA_HOME
    if ! grep -q "export JAVA_HOME=" ~/.bashrc; then
        {
            echo ""
            echo "# Set JAVA_HOME automatically"
            echo "export JAVA_HOME=${JAVA_PATH}"
            echo 'export PATH=$JAVA_HOME/bin:$PATH'
        } >> ~/.bashrc

        echo "[INFO] 已将 JAVA_HOME 添加到 ~/.bashrc"
    else
        echo "[INFO] JAVA_HOME 已存在于 ~/.bashrc, 跳过添加"
    fi

    echo "[INFO] Java version $jdk_ver is installed."
}

# 安装依赖
function install_dependencies() {
    install_jdk

    # install tar
    if command -v tar &> /dev/null; then
        echo "[INFO] tar 已安装，无需在次安装"
    else
        echo "[INFO] 安装 tar..."
        install_app tar
        echo "[INFO] 安装 tar 完成"
    fi
    # install curl
    if command -v curl &> /dev/null; then
        echo "[INFO] curl 已安装，无需在次安装"
    else
        echo "[INFO] 安装 curl..."
        install_app curl
        echo "[INFO] 安装 curl 完成"
    fi

}

function install_app(){
    echo "[INFO] 安装依赖: $1 ..."
    if [[ $OS_ID == "centos" ]]; then
        yum install -y $1
    elif [[ $OS_ID == "ubuntu" ]]; then
        apt update && apt install -y $1
    elif [[ $OS_ID == "sles" || $OS_ID == "suse" ]]; then
        zypper install -y $1
    else
        echo "[ERROR] 不支持的操作系统: $OS_ID"
        exit 1
    fi
}

# 版本比较函数：返回1代表大于等于2.8.0
function version_ge_280() {
    local version="$1"
    [ "$(printf '%s\n' "2.8.0" "$version" | sort -V | head -n1)" = "2.8.0" ]
}

# 安装 Kafka
function install_kafka() {
    echo "[INFO] 开始安装 Kafka ${KAFKA_VERSION}..."

    # ==== 卸载原有 Kafka（如存在） ====
    if [ -d "$INSTALL_DIR" ] && [ "$(ls -A "$INSTALL_DIR")" ]; then
        echo "[INFO] 检测到已有 Kafka 安装在 $INSTALL_DIR，准备卸载..."

        # 可选：备份旧目录
        BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%Y%m%d%H%M%S)"
        echo "[INFO] 备份现有 Kafka 到 $BACKUP_DIR"
        mv "$INSTALL_DIR" "$BACKUP_DIR"
    fi

    # ==== 下载 Kafka 安装包 ====
    echo "[INFO] 开始下载 Kafka ${KAFKA_VERSION} 安装包..."
    mkdir -p "$INSTALL_DIR"

    # 若/tmp/kafka.tgz存在，删除
    if [ -f /tmp/kafka.tgz ]; then
        echo "[INFO] 删除已存在的 /tmp/kafka.tgz"
        rm -f /tmp/kafka.tgz
    fi
    # Choose the appropriate mirror based on network environment
    if [[ $DOWNLOAD_URL != "undefined" ]]; then
        echo "[INFO] 使用指定的下载 URL: $DOWNLOAD_URL"
        curl -L "$DOWNLOAD_URL" -O /tmp/kafka.tgz
    else
        echo "[INFO] 未指定下载 URL，使用默认镜像下载 Kafka ${KAFKA_VERSION}..."
        if is_domestic; then
            echo "[INFO] Using domestic mirror for Kafka download."
            echo "[INFO] 下载地址：https://mirrors.tuna.tsinghua.edu.cn/apache/kafka/${KAFKA_VERSION}/kafka_2.13-${KAFKA_VERSION}.tgz"
            curl -L https://mirrors.tuna.tsinghua.edu.cn/apache/kafka/${KAFKA_VERSION}/kafka_2.13-${KAFKA_VERSION}.tgz -o /tmp/kafka.tgz
        else
            echo "[INFO] Using international mirror for Kafka download."
            echo "[INFO] 下载地址：https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_2.13-${KAFKA_VERSION}.tgz"
            curl -L https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_2.13-${KAFKA_VERSION}.tgz -o /tmp/kafka.tgz
        fi
    fi

    # 检查下载是否成功
    if [ $? -ne 0 ]; then
        echo "[ERROR] 下载 Kafka 失败，请检查网络连接或手动下载"
        exit 1
    fi

    tar -xzf /tmp/kafka.tgz -C "$INSTALL_DIR" --strip-components=1
    rm -f /tmp/kafka.tgz
}

function config_kafka(){
    local config_path="$INSTALL_DIR/config"
    # configure Kafka
    echo "[INFO] Configuring Kafka..."
    if [[ $SERVER_IP == "localhost" ]]; then
        echo "[INFO] 使用本机地址 作为 Kafka 广播地址"
        SERVER_IP=$(hostname -I | awk '{print $1}')
    else
        echo "[INFO] 使用指定的服务器 IP: $SERVER_IP 作为 Kafka 广播地址"
    fi

    if [[ "$USE_KRAFT" == "true" ]]; then
        config_path="$INSTALL_DIR/config/kraft"
    fi

    mkdir -p /opt/kafka/logs
    echo ${config_path}
    cp "${config_path}/server.properties" "${config_path}/server.properties.bak"
    sed -i "s|^log.dirs=.*|log.dirs=/opt/kafka/logs|" "${config_path}/server.properties"
    sed -i "s|^zookeeper.connect=.*|zookeeper.connect=localhost:2181|" "${config_path}/server.properties"
    if [[ "$USE_KRAFT" == "true" ]]; then
        sed -i "s|^listeners=.*|listeners=PLAINTEXT://:9092,CONTROLLER://:9093|" "${config_path}/server.properties"
    else
        sed -i "s|^listeners=.*|listeners=PLAINTEXT://:9092|" "${config_path}/server.properties"
    fi
    sed -i "s|^advertised.listeners=.*|advertised.listeners=PLAINTEXT://${SERVER_IP}:9092|" "${config_path}/server.properties"
    sed -i "s|^log.retention.hours=.*|log.retention.hours=1|" "${config_path}/server.properties"
}

# 创建 kafka 用户
function create_kafka_user() {
    id "$KAFKA_USER" &>/dev/null || useradd -r -s /sbin/nologin "$KAFKA_USER"
    chown -R "$KAFKA_USER":"$KAFKA_USER" "$INSTALL_DIR"
}

# 创建 systemd 服务
function create_systemd_service() {
    echo "[INFO] 创建 systemd 服务..."
    local service_file="/etc/systemd/system/kafka.service"

    if [[ "$DEPLOY_MODE" == "kraft" ]]; then
    echo "[INFO] Creating Kafka systemd（kraft model） service file..."
    cat <<EOF > "$service_file"
[Unit]
Description=Apache Kafka (KRaft mode)
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/bin/kafka-server-start.sh $INSTALL_DIR/config/kraft/server.properties
Restart=on-failure
LimitNOFILE=100000
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
    else
    echo "[INFO] Creating Kafka systemd（zookeeper model） service file..."
    cat <<EOF > "$service_file"
[Unit]
Description=Apache Kafka (Zookeeper mode)
After=network.target zookeeper.service

[Service]
Type=simple
ExecStart=$INSTALL_DIR/bin/kafka-server-start.sh $INSTALL_DIR/config/server.properties
Restart=on-failure
LimitNOFILE=100000
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    echo "[INFO] Creating Zookeeper systemd service file..."
    cat <<EOF > /etc/systemd/system/zookeeper.service
[Unit]
Description=Apache Zookeeper Service
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/bin/zookeeper-server-start.sh $INSTALL_DIR/config/zookeeper.properties
ExecStop=$INSTALL_DIR/bin/zookeeper-server-stop.sh
Restart=on-failure
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
    fi

    # 设置logs目录权限
    # chown -R "$KAFKA_USER":"$KAFKA_USER" "$INSTALL_DIR"/logs

    systemctl daemon-reload
    if [[ "$DEPLOY_MODE" == "zookeeper" ]]; then
        systemctl enable zookeeper
    fi
    systemctl enable kafka
}


# 判断是否启用 kraft
function detect_kraft_mode() {
    if [[ "$DEPLOY_MODE" == "kraft" ]]; then
        echo "[INFO] 使用 Kraft 模式部署 Kafka..."
        if version_ge_280 "$KAFKA_VERSION"; then
            USE_KRAFT="true"
            echo "[INFO] Kafka $KAFKA_VERSION 支持 Kraft 模式，启用 Kraft..."
            cp "$INSTALL_DIR/config/kraft/server.properties" "$INSTALL_DIR/config/kraft/server.properties.bak"
            # 初始化 Kraft 集群 (你需要替换 node-id 和 uuid)
            tmp_log_dir=$(grep -oP '(?<=^log.dirs=).*' "$INSTALL_DIR/config/kraft/server.properties")
            rm -rf $tmp_log_dir/*
            ${INSTALL_DIR}/bin/kafka-storage.sh format -t "$(uuidgen)" -c "$INSTALL_DIR/config/kraft/server.properties"
        else
            USE_KRAFT="false"
            echo "[INFO] Kafka $KAFKA_VERSION 不支持 Kraft 模式"
            echo "[INFO] 请使用 Zookeeper 模式部署 Kafka"
            return 1
        fi
    else
        echo "[INFO] 使用 Zookeeper 模式部署 Kafka..."
        USE_KRAFT="false"
    fi
    # ls -l $tmp_log_dir
}

start_service() {
    if [[ "$DEPLOY_MODE" == "zookeeper" ]]; then
        echo "[INFO] Starting Zookeeper service..."
        systemctl stop zookeeper
        rm -rf /opt/kafka/logs/*
        systemctl start zookeeper
        # Check if Zookeeper started successfully
        if ! systemctl is-active --quiet zookeeper; then
            echo "[ERROR] Failed to start Zookeeper service."
            exit 1
        fi
        echo "[INFO] Zookeeper service started successfully."
    fi

    echo "[INFO] Starting Kafka service..."
    systemctl stop kafka
    systemctl start kafka
    # Check if Kafka started successfully
    if ! systemctl is-active --quiet kafka; then
        echo "[ERROR] Failed to start Kafka service."
        exit 1
    fi
    echo "[INFO] Kafka service started successfully."
}

### 主流程
main() {
    check_privilege
    detect_os
    install_dependencies
    install_kafka
    # create_kafka_user
    config_kafka
    detect_kraft_mode
    create_systemd_service
    start_service
}

main "$@"
