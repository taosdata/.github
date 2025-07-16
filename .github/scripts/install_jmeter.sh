#!/bin/bash
set -e

JMETER_VERSION=${1:-5.6.3}
JDBC_VERSION=${2:-3.6.3}
JDBC_FILE_NAME="taos-jdbcdriver-${JDBC_VERSION}-dist.jar "
JDBC_DOWNLOAD_URL="https://repo1.maven.org/maven2/com/taosdata/jdbc/taos-jdbcdriver/${JDBC_VERSION}/${JDBC_FILE_NAME}"
JMETER_TGZ="apache-jmeter-${JMETER_VERSION}.tgz"
# DOWNLOAD_URL="https://dlcdn.apache.org/jmeter/binaries/${JMETER_TGZ}"
DOWNLOAD_URL="https://mirrors.huaweicloud.com/apache/jmeter/binaries/${JMETER_TGZ}"
INSTALL_BASE="/opt"
INSTALL_DIR="${INSTALL_BASE}/apache-jmeter-${JMETER_VERSION}"
LOCAL_TGZ="/tmp/jmeter/${JMETER_TGZ}"

# 检测是否为 root 或使用 sudo
if [ "$(id -u)" -ne 0 ]; then
    echo "需要 root 权限的用户运行脚本"
    exit 1
fi

# 判断操作系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
else
    echo "无法识别操作系统"
    exit 1
fi

# 修正部分 SUSE 系统
if grep -qi suse /etc/os-release; then
  OS_ID=suse
fi

echo "安装 Jmeter $JMETER_VERSION (系统: $OS_ID)"

# 安装依赖
install_dep() {
    PKG=$1
    if ! command -v "$PKG" >/dev/null; then
        echo "📦 安装依赖包: $PKG"
        case "$OS_ID" in
            ubuntu|debian)
                echo apt update -y && apt install -y "$PKG"
                apt update -y && apt install -y "$PKG"
                ;;
            centos|rhel|rocky|almalinux|kylin)
                echo yum install -y "$PKG"
                yum install -y "$PKG"
                ;;
            sles|suse|opensuse-leap|opensuse-tumbleweed)
                echo "zypper install -y $PKG"
                zypper install -y "$PKG"
                ;;
            *)
                echo "不支持的系统: $OS_ID"
                exit 1
                ;;
        esac
    fi
}

install_dep curl
install_dep tar

# 下载或使用本地包
if ls $LOCAL_TGZ >/dev/null 2>&1; then
    echo "使用本地包: $LOCAL_TGZ"
    cp "$LOCAL_TGZ" "$JMETER_TGZ"
else
    echo "联网正常，下载 JMeter..."
    curl -LO "$DOWNLOAD_URL"
fi

# 解压与软链接
echo "解压 JMeter 到 $INSTALL_DIR"
mkdir -p "$INSTALL_BASE"
tar -xzf "$JMETER_TGZ" -C "$INSTALL_BASE"

echo "创建软链接 /opt/jmeter -> $INSTALL_DIR"
ln -sfn "$INSTALL_DIR" "$INSTALL_BASE/jmeter"

echo "创建命令软链接 /usr/local/bin/jmeter"
ln -sfn "$INSTALL_BASE/jmeter/bin/jmeter" /usr/local/bin/jmeter

echo "下载JDBC驱动"
curl -LO "$JDBC_DOWNLOAD_URL"
echo "将JDBC驱动复制到JMeter的lib目录"
cp "$JDBC_FILE_NAME" "$INSTALL_BASE/jmeter/lib/"

echo 'export JMETER_HOME=/opt/jmeter' >> ~/.bashrc
echo 'export PATH=$JMETER_HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

echo "安装完成:"
jmeter -v
