#!/bin/bash
set -e

# 使用方法
# ./insitall_telegraf.sh 1.35.2-1 192.168.1.1 6041 testdb root taosdata
# ./insitall_telegraf.sh latest 192.168.1.1 6041 testdb root taosdata

TELEGRAF_VERSION=${1:-latest}

add_telegraf_http_output() {
  local ip="$1"
  local port="$2"
  local db="$3"
  local username="$4"
  local password="$5"

  # 删除旧的 [[outputs.http]] 区块（包含内容）
  # 注意：使用 awk 处理多行删除
  $SUDO awk '
   BEGIN { skip = 0 }
   /^\[\[outputs\.http\]\]/ { skip = 1; next }
   /^\[\[.*\]\]/ { skip = 0 }
   skip == 0 { print }
  ' /etc/telegraf/telegraf.conf | sudo tee /etc/telegraf/telegraf.conf.tmp > /dev/null

  $SUDO cat <<EOF | sudo tee -a /etc/telegraf/telegraf.conf.tmp > /dev/null
[[outputs.http]]
  url = "http://${ip}:${port}/influxdb/v1/write?db=${db}"
  method = "POST"
  timeout = "5s"
  username = "${username}"
  password = "${password}"
  data_format = "influx"
EOF
  # 替换原配置文件
  $SUDO mv "/etc/telegraf/telegraf.conf.tmp" "/etc/telegraf/telegraf.conf"
}

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

echo "安装 Telegraf(系统: $OS_ID)"

install_telegraf_deb() {
  if [[ "$1" == "latest" ]]; then
    TELEGRAF_VERSION="telegraf"
  else
    TELEGRAF_VERSION="telegraf=$1"
  fi

  if ls /tmp/telegraf/*.deb &>/dev/null; then
    echo "使用离线 .deb 安装 Telegraf..."
    $SUDO dpkg -i /tmp/telegraf/*.deb || $SUDO apt -f install -y
  else
    echo "在线安装 Telegraf (Debian/Ubuntu)"
    $SUDO apt update
    $SUDO apt install -y curl gnupg
    wget -qO influxdata.gpg https://repos.influxdata.com/influxdata-archive.key
    sudo install -m 644 -o root -g root influxdata.gpg /etc/apt/trusted.gpg.d/influxdata.gpg
    # curl -s https://repos.influxdata.com/influxdata-archive.key | $SUDO gpg --dearmor -o /etc/apt/trusted.gpg.d/influxdata.gpg
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/influxdata.gpg] https://repos.influxdata.com/ubuntu $(lsb_release -cs) stable" | $SUDO tee /etc/apt/sources.list.d/influxdata.list
    $SUDO apt update
    $SUDO apt install -y telegraf
  fi
}

install_telegraf_rpm() {
  if [[ "$1" == "latest" ]]; then
    TELEGRAF_VERSION="telegraf"
  else
    TELEGRAF_VERSION="telegraf-$1"
  fi

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
    $SUDO yum install -y telegraf --nogpgcheck
  fi
}

case "$OS_ID" in
  ubuntu|debian)
    install_telegraf_deb $TELEGRAF_VERSION
    ;;
  centos|rhel|rocky|almalinux|kylin|suse)
    install_telegraf_rpm $TELEGRAF_VERSION
    ;;
  *)
    echo "不支持的操作系统: $OS_ID"
    exit 1
    ;;
esac

# 启动 Telegraf
echo "启动 Telegraf 服务..."
$SUDO systemctl enable telegraf

if systemctl list-unit-files | grep -q '^telegraf.service'; then
    echo "Telegraf 已注册为 systemd 服务"
else
    echo "Telegraf 未注册"
    exit 1
fi

# 需要配置/etc/telegraf/telegraf.conf，设置outputs
add_telegraf_http_output $2 $3 $4 $5 $6

# 启动 Telegraf
echo "启动 Telegraf 服务..."
$SUDO systemctl restart telegraf

# 检查状态
echo "Telegraf 安装完成！当前状态："
$SUDO systemctl status telegraf --no-pager
