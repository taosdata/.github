#!/bin/bash
set -e

# Usage: ./install_influxdb.sh <INFLUXDB_VERSION> <INFLUXDB_PORT> <INFLUXDB_DATA_DIR>
# INFLUXDB_VERSION：influxdb的版本号，默认值：2.7.11
# INFLUXDB_PORT：influxdb占用端口号，默认值：8086
# INFLUXDB_DATA_DIR：influxdb的数据目录，默认值：/var/lib/influxdb

# 配置参数
INFLUXDB_VERSION=${1:-"2.7.11"}
INFLUXDB_PORT=${2:-"8086"}
INFLUXDB_DATA_DIR=${3:-"/var/lib/influxdb"}

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# 检测系统类型和架构
detect_system() {
    if [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/alpine-release ]; then
        echo "alpine"
    else
        echo "unknown"
    fi
}

detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        *) echo "$ARCH" ;;
    esac
}

# 安装依赖
install_dependencies() {
    log_info "安装系统依赖..."
    OS_TYPE=$(detect_system)
    
    case $OS_TYPE in
        "rhel")
            yum install -y curl wget tar gzip
            ;;
        "debian")
            apt-get update
            apt-get install -y curl wget tar gzip
            ;;
        "alpine")
            apk add --no-cache curl wget tar gzip
            ;;
        *)
            if command -v yum &> /dev/null; then
                yum install -y curl wget tar gzip
            elif command -v apt-get &> /dev/null; then
                apt-get update
                apt-get install -y curl wget tar gzip
            elif command -v apk &> /dev/null; then
                apk add --no-cache curl wget tar gzip
            fi
            ;;
    esac
}

# 方法1：使用官方安装脚本
install_via_official_script() {
    log_info "使用官方脚本安装 InfluxDB..."
    
    # 下载并运行官方安装脚本
    mkdir -p /usr/share/keyrings/
    if [ -f "/usr/share/keyrings/influxdata-archive-keyring.gpg" ]; then
        rm -f /usr/share/keyrings/influxdata-archive-keyring.gpg
    fi 
    curl -fsSL https://repos.influxdata.com/influxdata-archive.key | gpg --dearmor -o /usr/share/keyrings/influxdata-archive-keyring.gpg
    
    OS_TYPE=$(detect_system)
    case $OS_TYPE in
        "debian")
            echo "deb [signed-by=/usr/share/keyrings/influxdata-archive-keyring.gpg] https://repos.influxdata.com/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/influxdb.list
            apt-get update
            if [ "$INFLUXDB_VERSION" = "latest" ]; then
                apt-get install -y influxdb2
            else
                apt-get install -y influxdb2=$INFLUXDB_VERSION*
            fi
            ;;
        "rhel")
            cat <<EOF > /etc/yum.repos.d/influxdb.repo
[influxdb]
name = InfluxDB Repository
baseurl = https://repos.influxdata.com/rhel/\$releasever/\$basearch/stable
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdata-archive.key
EOF
            yum clean all
            yum makecache
            if [ "$INFLUXDB_VERSION" = "latest" ]; then
                yum install -y influxdb2 --nogpgcheck
            else
                yum install -y influxdb2-$INFLUXDB_VERSION --nogpgcheck
            fi
            ;;
        *)
            log_error "不支持的系统类型"
            return 1
            ;;
    esac
}

# 方法2：从 GitHub Releases 下载
install_via_github_release() {
    log_info "从 GitHub Releases 下载 InfluxDB..."
    
    ARCH=$(detect_arch)
    
    # GitHub Releases 的下载URL
    if [[ "$INFLUXDB_VERSION" == 1.* ]]; then
        DOWNLOAD_URL="https://dl.influxdata.com/influxdb/releases/influxdb-${INFLUXDB_VERSION}_linux_${ARCH}.tar.gz"
    else
        DOWNLOAD_URL="https://dl.influxdata.com/influxdb/releases/influxdb2-${INFLUXDB_VERSION}_linux_${ARCH}.tar.gz"
    fi

    log_info "下载地址: $DOWNLOAD_URL"
    
    # 下载
    wget -O /tmp/influxdb.tar.gz "$DOWNLOAD_URL" || {
        log_error "下载失败，尝试备用镜像..."
        exit 1
    }
    
    # 解压
    tar xzf /tmp/influxdb.tar.gz -C /tmp
    
    # 移动到安装目录
    if [ -d "/opt/influxdb" ]; then
        rm -rf /opt/influxdb
    fi

    if [[ "$INFLUXDB_VERSION" == 1.* ]]; then
        mv "/tmp/influxdb_${INFLUXDB_VERSION}_1" /opt/influxdb
    else
        mv "/tmp/influxdb2-${INFLUXDB_VERSION}" /opt/influxdb
    fi
    
    setup_influxdb_service
}

# 设置系统服务
setup_influxdb_service() {
    log_info "设置 InfluxDB 系统服务..."
    
    # 创建用户
    if ! id "influxdb" &> /dev/null; then
        useradd -r -s /bin/false influxdb
    fi
    
    # 创建数据目录
    mkdir -p "$INFLUXDB_DATA_DIR"
    chown -R influxdb:influxdb "$INFLUXDB_DATA_DIR"
    chown -R influxdb:influxdb /opt/influxdb
    
    # 创建服务文件
    cat <<EOF > /etc/systemd/system/influxdb.service
[Unit]
Description=InfluxDB Time Series Database
Documentation=https://docs.influxdata.com/influxdb/
After=network.target

[Service]
User=influxdb
Group=influxdb
ExecStart=/opt/influxdb/usr/bin/influxd
WorkingDirectory=/opt/influxdb
Environment=INFLUXD_BOLT_PATH=${INFLUXDB_DATA_DIR}/influxdb.bolt
Environment=INFLUXD_ENGINE_PATH=${INFLUXDB_DATA_DIR}/engine
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    
    # 启用并启动服务
    systemctl daemon-reload
    systemctl enable influxdb
    systemctl start influxdb
}

# 方法3：使用 Docker 安装
install_via_docker() {
    log_info "使用 Docker 安装 InfluxDB $INFLUXDB_VERSION..."
    
    # 检查并安装 Docker
    if ! command -v docker &> /dev/null; then
        log_info "安装 Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl start docker
        systemctl enable docker
    fi
    
    # 停止并移除现有容器
    docker stop influxdb 2>/dev/null || true
    docker rm influxdb 2>/dev/null || true
    
    # 创建数据目录
    mkdir -p "$INFLUXDB_DATA_DIR"
    chmod 777 "$INFLUXDB_DATA_DIR"
    
    # 运行 InfluxDB 容器
    docker run -d \
        --name influxdb \
        -p "$INFLUXDB_PORT":8086 \
        -v "$INFLUXDB_DATA_DIR":/var/lib/influxdb2 \
        -e DOCKER_INFLUXDB_INIT_MODE=setup \
        -e DOCKER_INFLUXDB_INIT_USERNAME=admin \
        -e DOCKER_INFLUXDB_INIT_PASSWORD=admin123 \
        -e DOCKER_INFLUXDB_INIT_ORG=myorg \
        -e DOCKER_INFLUXDB_INIT_BUCKET=mybucket \
        -e INFLUXD_HTTP_BIND_ADDRESS=":$INFLUXDB_PORT" \
        --restart unless-stopped \
        "influxdb:${INFLUXDB_VERSION}"
    
    log_info "Docker 容器已启动"
}

# 检查服务状态
check_service_status() {
    local max_attempts=60
    local attempt=1
    
    log_info "检查 InfluxDB 服务状态..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "http://localhost:$INFLUXDB_PORT/health" >/dev/null 2>&1; then
            log_info "✅ InfluxDB 服务已启动并运行正常"
            return 0
        fi
        
        log_info "⏳ 等待 InfluxDB 启动... ($attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done
    
    log_warn "InfluxDB 服务启动超时，请手动检查"
    return 1
}

# 显示安装信息
show_installation_info() {
    log_info "🎉 InfluxDB 安装完成！"
    echo ""
    echo "版本: InfluxDB $INFLUXDB_VERSION"
    echo "端口: $INFLUXDB_PORT"
    echo "数据目录: $INFLUXDB_DATA_DIR"
    echo "健康检查: curl http://localhost:$INFLUXDB_PORT/health"
    echo ""
    
    if [ "$INSTALL_METHOD" = "docker" ]; then
        echo "初始登录信息:"
        echo "用户名: admin"
        echo "密码: admin123"
        echo "组织: myorg"
        echo "桶: mybucket"
        echo ""
        echo "管理界面: http://localhost:$INFLUXDB_PORT"
    fi
    echo ""
}

# 主函数
main() {
    log_info "开始安装 InfluxDB $INFLUXDB_VERSION..."
    
    install_dependencies
    
    # 自动选择最佳安装方式
    if command -v docker &> /dev/null; then
        INSTALL_METHOD="docker"
        install_via_docker
    else
        INSTALL_METHOD="native"
        if ! install_via_official_script; then
            log_warn "官方脚本安装失败，尝试 GitHub Releases 安装"
            install_via_github_release
        fi
    fi
    
    if check_service_status; then
        show_installation_info
    else
        log_warn "InfluxDB 可能仍在启动中"
        if [ "$INSTALL_METHOD" = "docker" ]; then
            log_info "查看 Docker 日志: docker logs influxdb"
        else
            log_info "查看系统日志: journalctl -u influxdb -f"
        fi
    fi
}

# 执行主函数
main "$@"