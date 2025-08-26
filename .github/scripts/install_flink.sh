#!/bin/bash
set -e

# Usage: ./install_flink.sh <FLINK_VERSION> <SCALA_VERSION> <JAVA_VERSION> <INSTALL_JAVA> <INSTALL_DIR> <FLINK_USER>
# FLINK_VERSION: flink的版本号，默认值：1.17.2
# SCALA_VERSION: scala的版本号，默认值：2.12
# JAVA_VERSION: Java的版本号，默认值：11
# INSTALL_JAVA: 是否安装Java，默认值：true
# INSTALL_DIR: influxdb的安装目录，默认值：/opt/flink
# FLINK_USER: influxdb的用户，默认值：flink

# 下表列出了不同 Flink 版本与 Java 版本的对应关系，本脚本安装java11，若要安装Flink 1.8，需要安装 Java 8。
# | **Flink 版本**      | **最低支持的 Java 版本** | **最高支持的 Java 版本** | 说明                             |
# | ------------------ | ----------------- | ----------------- | ----------------------------------------- |
# | Flink 1.8 及以下    | Java 8            | Java 8            | 仅支持 Java 8                              |
# | Flink 1.9 \~ 1.11  | Java 8            | Java 11           | Java 11 支持较新，推荐 Java 8                |
# | Flink 1.12 \~ 1.14 | Java 8            | Java 11           | 推荐 Java 11                               |
# | Flink 1.15         | Java 8            | Java 17           | 开始支持 Java 17（实验性），仍推荐 Java 11     |
# | Flink 1.16         | Java 8            | Java 17           | Java 11 是最佳选择                          |
# | Flink 1.17 \~ 1.18 | Java 8            | Java 17           | Java 11 推荐，Java 17 可用                  |
# | Flink 1.19+        | Java 11           | Java 21           | 官方逐步淘汰 Java 8，Java 11 / 17 / 21 都支持 |

# 配置参数
FLINK_VERSION="${1:-1.17.2}"
SCALA_VERSION="${2:-2.12}"
JAVA_VERSION="${3:-11}"
INSTALL_JAVA="${4:-true}"  # 是否自动安装 Java，默认 true
INSTALL_DIR="${5:-/opt/flink}"
FLINK_USER="${6:-flink}"

DOWNLOAD_URL=""
OS=""
OS_NAME=""
OS_VERSION=""

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$ID"
        OS_VERSION="$VERSION_ID"
    elif [ -f /etc/redhat-release ]; then
        OS_NAME="centos"
        OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release || echo "7")
    elif [ -f /etc/SuSE-release ]; then
        OS_NAME="suse"
        OS_VERSION=$(grep VERSION /etc/SuSE-release | awk '{print $3}')
    else
        OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$(uname -r)
    fi
}

# 检测系统架构
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "$ARCH" ;;
    esac
}

# 检查 Java 是否已安装
check_java_installed() {
    log_info "检查 Java 安装状态..."
    
    # 检查 java 命令是否存在
    if command -v java &> /dev/null; then
        JAVA_CMD=$(which java)
        log_info "Java 已安装: $JAVA_CMD"
        
        # 获取 Java 版本
        JAVA_VERSION_INSTALLED=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')
        log_info "Java 版本: $JAVA_VERSION_INSTALLED"
        
        if [[ "$JAVA_VERSION_INSTALLED" == *"$JAVA_VERSION"* ]]; then
            log_info "Java 版本符合要求: $JAVA_VERSION_INSTALLED"
        else
            log_warn "Java 版本不符合要求: $JAVA_VERSION_INSTALLED (需要 $JAVA_VERSION)"
            return 1
        fi

        return 0
    else
        log_warn "Java 未安装"
        return 1
    fi
}

# 检查 JAVA_HOME 是否配置
check_java_home() {
    log_info "检查 JAVA_HOME 配置..."
    
    # 检查环境变量
    if [ -n "$JAVA_HOME" ]; then
        log_info "JAVA_HOME 环境变量已设置: $JAVA_HOME"
        
        # 检查路径是否存在
        if [ -d "$JAVA_HOME" ]; then
            log_info "JAVA_HOME 路径存在"
            
            # 检查 bin/java 是否存在
            if [ -f "$JAVA_HOME/bin/java" ]; then
                log_info "JAVA_HOME/bin/java 存在"
                return 0
            else
                log_warn "⚠️  JAVA_HOME/bin/java 不存在"
                return 1
            fi
        else
            log_warn "JAVA_HOME 路径不存在: $JAVA_HOME"
            return 1
        fi
    else
        log_warn "JAVA_HOME 环境变量未设置"
        return 1
    fi
}

# 自动检测 JAVA_HOME
detect_java_home() {
    # log_info "自动检测 JAVA_HOME..."
    
    # 方法1: 从 java 命令推导
    if command -v java &> /dev/null; then
        local java_path=$(readlink -f $(which java))
        local detected_home=$(dirname $(dirname "$java_path"))
        
        if [ -d "$detected_home" ]; then
            echo "$detected_home"
            # log_info "从 java 命令检测到: $detected_home"
            return 0
        fi
    fi
    
    # 方法2: 查找常见的 Java 安装路径
    local common_paths=(
        "/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64"
        "/usr/lib/jvm/java-${JAVA_VERSION}-openjdk"
        "/usr/lib/jvm/jre-${JAVA_VERSION}-openjdk"
        "/usr/lib/jvm/java-${JAVA_VERSION}-oracle"
        "/usr/java/jdk${JAVA_VERSION}"
        "/usr/java/latest"
        "/opt/java/jdk${JAVA_VERSION}"
        "/usr/lib/jvm/default-java"
    )
    
    for path in "${common_paths[@]}"; do
        if [ -d "$path" ] && [ -f "$path/bin/java" ]; then
            # log_info "找到 Java 安装: $path"
            echo "$path"
            return 0
        fi
    done
    
    # 方法3: 使用 update-alternatives
    if command -v update-alternatives &> /dev/null; then
        local alt_java=$(update-alternatives --list java 2>/dev/null | head -n 1)
        if [ -n "$alt_java" ]; then
            local detected_home=$(dirname $(dirname "$alt_java"))
            # log_info "从 update-alternatives 检测到: $detected_home"
            echo "$detected_home"
            return 0
        fi
    fi
    
    log_error "无法自动检测 JAVA_HOME"
    return 1
}

# 配置 JAVA_HOME
setup_java_home() {
    local java_home="$1"
    
    log_info "配置 JAVA_HOME: $java_home"
    
    # 检查是否需要配置
    if [ -n "$JAVA_HOME" ] && [ "$JAVA_HOME" = "$java_home" ]; then
        log_info "JAVA_HOME 已正确配置"
        return 0
    fi
    
    # # 配置到 /etc/environment
    # if ! grep -q "JAVA_HOME=" /etc/environment; then
    #     echo "JAVA_HOME=$java_home" | tee -a /etc/environment >/dev/null
    #     log_info "已添加到 /etc/environment"
    # else
    #     sed -i "s|^JAVA_HOME=.*|JAVA_HOME=$java_home|" /etc/environment
    #     log_info "已更新 /etc/environment"
    # fi
    
    PROFILE_FILE="/etc/profile.d/java.sh"

    # 配置到 profile.d
    cat << EOF | tee $PROFILE_FILE >/dev/null
export JAVA_HOME=$java_home
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
    
    log_info "已创建 $PROFILE_FILE"
    
    # 立即生效
    source $PROFILE_FILE
    
    log_info "环境变量已立即生效"
    return 0
}

# 安装 Java
install_java() {
    log_info "开始安装 Java ${JAVA_VERSION}"
    
    case $OS_NAME in
        ubuntu|debian)
            apt update
            apt install -y openjdk-${JAVA_VERSION}-jdk
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                dnf install -y java-${JAVA_VERSION}-openjdk java-${JAVA_VERSION}-openjdk-devel
            else
                yum install -y java-${JAVA_VERSION}-openjdk java-${JAVA_VERSION}-openjdk-devel
            fi
            ;;
        opensuse*|suse*)
            zypper refresh
            zypper install -y java-${JAVA_VERSION}-openjdk java-${JAVA_VERSION}-openjdk-devel
            ;;
        *)
            log_error "不支持的操作系统: $OS_NAME"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        log_info "Java ${JAVA_VERSION} 安装成功"
        return 0
    else
        log_error "Java ${JAVA_VERSION} 安装失败"
        return 1
    fi
}

# 验证 Java 安装
verify_java_installation() {
    log_info "验证 Java 安装..."
    
    # 检查 java 命令
    if ! command -v java &> /dev/null; then
        log_error "java 命令不存在"
        return 1
    fi
    
    # 检查版本
    local version=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')
    if [ -z "$version" ]; then
        log_error "无法获取 Java 版本"
        return 1
    fi
    
    log_info "✅ Java 版本: $version"
    
    # 检查 JAVA_HOME
    if [ -z "$JAVA_HOME" ]; then
        log_error "JAVA_HOME 未设置"
        return 1
    fi
    
    # 检查 JAVA_HOME 路径
    if [ ! -d "$JAVA_HOME" ]; then
        log_error "JAVA_HOME 路径不存在: $JAVA_HOME"
        return 1
    fi
    
    # 检查 java 可执行文件
    if [ ! -f "$JAVA_HOME/bin/java" ]; then
        log_error "$JAVA_HOME/bin/java 不存在"
        return 1
    fi
    
    return 0
}

check_and_install_java(){
    echo "Java 安装和配置脚本"
    echo "========================"
    
    # 检查 Java 是否已安装
    if check_java_installed; then
        log_info "Java 已安装"
    else
        if [ "$INSTALL_JAVA" = "true" ]; then
            log_info "开始安装 Java ${JAVA_VERSION}..."
            if ! install_java; then
                log_error "Java ${JAVA_VERSION} 安装失败"
                exit 1
            fi
        else
            log_error "Java 未安装且未启用自动安装"
            exit 1
        fi
    fi
    
    # 检查 JAVA_HOME
    if check_java_home; then
        log_info "JAVA_HOME 已正确配置"
    else
        log_info "自动检测 JAVA_HOME..."
        local detected_home=$(detect_java_home)
        if [ $? -eq 0 ]; then
            setup_java_home "$detected_home"
        else
            log_error "无法检测 JAVA_HOME，请手动设置"
            exit 1
        fi
    fi
    
    # 验证安装
    if verify_java_installation; then
        log_info "Java 安装验证通过"
    else
        log_error "Java 安装验证失败"
        exit 1
    fi
}


# 安装依赖（多平台支持）
install_dependencies() {
    log_info "安装系统依赖..."
    
    case $OS_NAME in
        ubuntu|debian)
            install_dependencies_debian
            ;;
        centos|rhel|fedora|amzn)
            install_dependencies_redhat
            ;;
        opensuse*|suse*)
            install_dependencies_suse
            ;;
        *)
            log_error "位置操作系统！"
            exit 1
            ;;
    esac
}

# Debian/Ubuntu 依赖
install_dependencies_debian() {
    apt-get update
    apt-get install -y \
        curl wget tar gzip \
        python3 python3-pip \
        ssh rsync
}

# RedHat/CentOS 依赖
install_dependencies_redhat() {
    if command -v dnf &> /dev/null; then
        dnf install -y \
            curl wget tar gzip \
            python3 python3-pip \
            openssh-clients rsync
    else
        yum install -y \
            curl wget tar gzip \
            python3 python3-pip \
            openssh-clients rsync
    fi
}

# SUSE 依赖
install_dependencies_suse() {
    if command -v zypper &> /dev/null; then
        zypper refresh
        zypper install -y \
            curl wget tar gzip \
            python3 python3-pip \
            openssh rsync
    else
        log_error "SUSE 系统需要 zypper 包管理器"
        exit 1
    fi
}

# 选择最佳镜像（多平台优化）
get_best_mirror() {
    local mirrors=()
    
    # 根据操作系统选择镜像优先级
    mirrors=(
        "https://mirrors.tuna.tsinghua.edu.cn/apache/flink"
        "https://mirrors.aliyun.com/apache/flink"
        "https://archive.apache.org/dist/flink"
    )
    
    # 测试镜像可用性
    for mirror in "${mirrors[@]}"; do
        if curl --silent --head --fail --max-time 5 "$mirror" >/dev/null 2>&1; then
            echo "$mirror"
            return 0
        fi
    done
    
    log_error "所有镜像都不可用"
    exit 1
}

# 创建系统用户（多平台兼容）
create_flink_user() {
    if ! id "$FLINK_USER" &> /dev/null; then
        log_info "创建用户: $FLINK_USER"
        
        case $os in
            ubuntu|debian)
                useradd --system --create-home --shell /bin/bash "$FLINK_USER"
                ;;
            centos|rhel|fedora)
                useradd --system --create-home --shell /bin/bash "$FLINK_USER"
                ;;
            opensuse*|suse*)
                useradd --system --create-home --shell /bin/bash "$FLINK_USER"
                ;;
            *)
                useradd --system --create-home --shell /bin/bash "$FLINK_USER"
                ;;
        esac
    fi
}

# 下载 Flink（多平台优化）
download_flink() {
    local mirror=$(get_best_mirror)
    if [ $? -ne 0 ]; then
        log_error "无法找到可用的镜像"
        exit 1
    fi
    
    local filename="flink-${FLINK_VERSION}-bin-scala_${SCALA_VERSION}.tgz"
    local download_url="${mirror}/flink-${FLINK_VERSION}/${filename}"
    
    log_info "使用镜像: $mirror"
    log_info "下载 Flink ${FLINK_VERSION}"
    
    if ! curl -fSL --progress-bar --connect-timeout 30 "$download_url" -o "/tmp/${filename}"; then
        log_error "下载失败"
        return 1
    fi
    
    return 0
}

# 安装和配置 Flink
install_flink() {
    log_info "安装 Flink 到: $INSTALL_DIR"
    
    # 清理旧安装
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    
    # 解压
    tar -xzf "/tmp/flink-${FLINK_VERSION}-bin-scala_${SCALA_VERSION}.tgz" -C "/tmp"
    mv "/tmp/flink-${FLINK_VERSION}"/* "$INSTALL_DIR/"
    
    # 设置权限
    chown -R "$FLINK_USER:$FLINK_USER" "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
}

# 配置环境变量（多平台兼容）
setup_environment() {
    log_info "配置环境变量"
    
    # 设置 JAVA_HOME（如果尚未设置）
    if [ -z "$JAVA_HOME" ]; then
        if [ -d "/usr/lib/jvm/java-17-openjdk" ]; then
            export JAVA_HOME="/usr/lib/jvm/java-17-openjdk"
        elif [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
            export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
        elif command -v java &> /dev/null; then
            export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
        fi
    fi
    
    # 创建环境变量文件
    cat << EOF | tee /etc/profile.d/flink.sh > /dev/null
export FLINK_HOME=$INSTALL_DIR
export PATH=\$FLINK_HOME/bin:\$PATH
export JAVA_HOME=${JAVA_HOME}
EOF
    
    # 立即生效
    source /etc/profile.d/flink.sh
}

# 创建系统服务（多平台兼容）
create_service() {
    local service_file=""
    
    case $OS_NAME in
        ubuntu|debian|centos|rhel|fedora)
            service_file="/etc/systemd/system/flink.service"
            create_systemd_service
            ;;
        opensuse*|suse*)
            service_file="/etc/systemd/system/flink.service"
            create_systemd_service
            ;;
        *)
            log_warn "未知操作系统，跳过服务创建"
            return 0
            ;;
    esac
}

# 创建 systemd 服务
create_systemd_service() {
    cat << EOF | tee /etc/systemd/system/flink.service > /dev/null
[Unit]
Description=Apache Flink Service
After=network.target

[Service]
Type=forking
User=$FLINK_USER
Group=$FLINK_USER
Environment=FLINK_HOME=$INSTALL_DIR
Environment=JAVA_HOME=$JAVA_HOME
ExecStart=$INSTALL_DIR/bin/start-cluster.sh
ExecStop=$INSTALL_DIR/bin/stop-cluster.sh
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}

# 配置 Flink
configure_flink() {
    local conf_dir="$INSTALL_DIR/conf"
    
    log_info "配置 Flink"
    
    # 备份原有配置
    cp "${conf_dir}/flink-conf.yaml" "${conf_dir}/flink-conf.yaml.backup" 2>/dev/null || true
    
    # 获取系统内存信息（MB）
    local total_mem=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
    local jm_mem=$((total_mem * 2 / 10))   # 20% 给 JobManager
    local tm_mem=$((total_mem * 6 / 10))   # 60% 给 TaskManager
    
    # 确保最小值
    jm_mem=$(( jm_mem < 1024 ? 1024 : jm_mem ))
    tm_mem=$(( tm_mem < 2048 ? 2048 : tm_mem ))
    
    cat << EOF | tee "${conf_dir}/flink-conf.yaml" > /dev/null
jobmanager.rpc.address: localhost
jobmanager.rpc.port: 6123
jobmanager.memory.process.size: ${jm_mem}m
taskmanager.memory.process.size: ${tm_mem}m
taskmanager.numberOfTaskSlots: $(nproc)
parallelism.default: 1
io.tmp.dirs: /tmp
fs.default-scheme: file
EOF

    # 配置 slaves（工作节点）
    echo "localhost" | tee "${conf_dir}/workers" > /dev/null
}

# 验证安装
verify_installation() {
    log_info "验证安装"
    
    # 检查文件
    local required_files=(
        "$INSTALL_DIR/bin/flink"
        "$INSTALL_DIR/bin/start-cluster.sh"
        "$INSTALL_DIR/conf/flink-conf.yaml"
    )
    
    for file in "${required_files[@]}"; do
        echo $file
        if [ ! -f "$file" ]; then
            log_error "缺少文件: $file"
            return 1
        fi
    done
    
    # 检查版本
    if ! "$INSTALL_DIR/bin/flink" --version &> /dev/null; then
        log_error "Flink 版本检查失败"
        return 1
    fi
    
    log_info "Flink 安装验证成功"
    return 0
}

# 显示安装信息
show_installation_info() {
    cat << EOF

Flink 安装完成！

平台: ${OS_NAME} ($(detect_arch))
版本: ${FLINK_VERSION}
Scala: ${SCALA_VERSION}
安装目录: ${INSTALL_DIR}
用户: ${FLINK_USER}
Java: ${JAVA_HOME}

常用命令:
  启动: systemctl start flink
  停止: systemctl stop flink
  状态: systemctl status flink
  命令行: flink run

Web UI: http://localhost:8081

环境变量已配置，重新登录后生效或运行:
  source /etc/profile.d/flink.sh

EOF
}

start_flink(){
    systemctl start flink
    sleep 5  # 等待服务启动
    log_info "检查 Web UI (http://localhost:8081)..."
    if curl -s --head --request GET http://localhost:8081 | grep "200 OK" >/dev/null; then
        log_info "Web UI 可访问"
    else
        log_error "Web UI 无法访问，请检查防火墙或 JobManager 是否启动"
    fi
}

# 主函数
main() {
    log_info "开始安装 Apache Flink ${FLINK_VERSION}"
    log_info "=========================================="
    
    # 检测操作系统
    detect_os
    log_info "操作系统: $OS_NAME"
    
    # 安装依赖
    install_dependencies

    # 安装JAVA
    check_and_install_java

    # 创建用户
    create_flink_user
    
    # 下载
    if ! download_flink; then
        log_error "下载失败"
        exit 1
    fi
    
    # 安装
    install_flink
    
    # 配置
    setup_environment
    configure_flink
    
    # 创建服务
    create_service
    
    # 验证
    if verify_installation; then
        show_installation_info
        start_flink
    else
        log_error "安装验证失败"
        exit 1
    fi
}

# 执行主函数
main "$@"