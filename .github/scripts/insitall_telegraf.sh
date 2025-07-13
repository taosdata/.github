#!/bin/bash
set -e

# 判断是否有 sudo 权限
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
    SUDO="sudo"
  else
    echo "请使用 root 用户或有 sudo 权限的用户运行此脚本"
    exit 1
  fi
else
  SUDO=""
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

echo "安装 Nginx(系统: $OS_ID)"

install_telegraf_deb() {
  if ls /tmp/telegraf/*.deb &>/dev/null; then
    echo "使用离线 .deb 安装 Telegraf..."
    $SUDO dpkg -i /tmp/telegraf/*.deb || $SUDO apt -f install -y
  else
    echo "在线安装 Telegraf (Debian/Ubuntu)"
    $SUDO apt update
    $SUDO apt install -y curl gnupg
    curl -s https://repos.influxdata.com/influxdata-archive.key | $SUDO gpg --dearmor -o /etc/apt/trusted.gpg.d/influxdata.gpg
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/influxdata.gpg] https://repos.influxdata.com/ubuntu $(lsb_release -cs) stable" | $SUDO tee /etc/apt/sources.list.d/influxdata.list
    $SUDO apt update
    $SUDO apt install -y telegraf
  fi
}

install_telegraf_rpm() {
  if ls /tmp/telegraf/*.rpm &>/dev/null; then
    echo "使用离线 .rpm 安装 Telegraf..."
    $SUDO rpm -Uvh /tmp/telegraf/*.rpm
  else
    echo "在线安装 Telegraf (RHEL/CentOS/SUSE)"
    $SUDO yum install -y curl
    $SUDO rpm --import https://repos.influxdata.com/influxdata-archive.key
    cat <<EOF | $SUDO tee /etc/yum.repos.d/influxdata.repo
[influxdata]
name = InfluxData Repository
baseurl = https://repos.influxdata.com/rhel/$(rpm -E %{rhel})/\$basearch/stable
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdata-archive.key
EOF
    $SUDO yum install -y telegraf
  fi
}

case "$OS_ID" in
  ubuntu|debian)
    install_telegraf_deb
    ;;
  centos|rhel|rocky|almalinux|kylin|suse)
    install_telegraf_rpm
    ;;
  *)
    echo "不支持的操作系统: $OS_ID"
    exit 1
    ;;
esac

# 启动 Telegraf
echo "启动 Telegraf 服务..."
$SUDO systemctl enable telegraf
$SUDO systemctl restart telegraf

# 检查状态
echo "Telegraf 安装完成！当前状态："
$SUDO systemctl status telegraf --no-pager
