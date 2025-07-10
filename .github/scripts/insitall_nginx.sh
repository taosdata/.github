#!/bin/bash
set -e

LISTEN_PORT=${1:-80}
HTML_DIR="/usr/share/nginx/html"
CUSTOM_INDEX="$HTML_DIR/index.html"
# NGINX_PACK="apache-jmeter-${JMETER_VERSION}.tgz"
LOCAL_PACK="/tmp/nginx"

# 检查权限
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
    SUDO="sudo"
  else
    echo "需要 root 或 sudo 权限"
    exit 1
  fi
else
  SUDO=""
fi

# 判断系统
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID=$ID
else
  echo "无法识别系统类型"
  exit 1
fi

# 修正部分 SUSE 系统
if grep -qi suse /etc/os-release; then
  OS_ID=suse
fi

echo "安装 Nginx(系统: $OS_ID)"

install_nginx_deb() {
  if ls $LOCAL_PACK/*.deb >/dev/null 2>&1; then
    echo "离线安装 DEB 包..."
    $SUDO dpkg -i $LOCAL_PACK/*.deb || $SUDO apt -f install -y
  else
    echo "在线安装 nginx (Ubuntu)"
    $SUDO apt update && $SUDO apt install -y nginx
  fi
}

install_nginx_rpm() {
  if ls $LOCAL_PACK/*.deb >/dev/null 2>&1; then
    echo "离线安装 RPM 包..."
    $SUDO rpm -Uvh --force $LOCAL_PACK/*.rpm
  else
    echo "在线安装 nginx (CentOS)"
    $SUDO yum install -y epel-release && $SUDO yum install -y nginx
  fi
}

install_nginx_rpm_suse() {
  if ls $LOCAL_PACK/*.deb >/dev/null 2>&1; then
    echo "离线安装 RPM 包..."
    $SUDO rpm -Uvh --force $LOCAL_PACK/*.rpm
  else
    echo "在线安装 nginx (CentOS)"
    $SUDO zypper refresh
    $SUDO zypper install -y nginx
  fi
}


case "$OS_ID" in
  ubuntu|debian)
    install_nginx_deb
    ;;
  centos|rhel|kylin|rocky|almalinux)
    install_nginx_rpm
    ;;
  opensuse|suse|sles)
    install_nginx_rpm_suse
    ;;
  *)
    echo "暂不支持的系统: $OS_ID"
    exit 1
    ;;
esac

# 修改监听端口
echo "修改默认端口为 $LISTEN_PORT"
NGINX_CONF="/etc/nginx/sites-available/default"
if [ -f "$NGINX_CONF" ]; then
  $SUDO sed -i "s/listen 80 default_server;/listen $LISTEN_PORT default_server;/g" "$NGINX_CONF"
else
  # RHEL/CentOS 使用 nginx.conf
  $SUDO sed -i "s/listen\s*80;/listen $LISTEN_PORT;/g" /etc/nginx/nginx.conf
fi

# 设置默认页面
echo "配置默认首页"
$SUDO bash -c "cat > $CUSTOM_INDEX" <<EOF
<!DOCTYPE html>
<html>
  <head><title>Nginx Installed</title></head>
  <body><h1>Nginx 安装成功！</h1><p>监听端口: $LISTEN_PORT</p></body>
</html>
EOF

# 启动 nginx
$SUDO systemctl enable nginx
$SUDO systemctl restart nginx

# 验证
echo "Nginx 运行中："
$SUDO systemctl status nginx --no-pager
