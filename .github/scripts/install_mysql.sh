#!/bin/bash

set -e
# set -x

# 版本号可以通过命令行参数传入，默认版本为 8.0
# Usage: ./install_mysql.sh <version>
# version: 5.5, 5.6, 5.7, 8.0
# ubuntu系统仅支持 mysql 8.0+

MYSQL_VERSION="${1:-8.0}"
NEW_ROOT_PASSWORD="MyNewPassw0rd!"

# 用户权限级别校验
check_privilege(){
    if [ "$(id -u)" -ne 0 ]; then
        echo "[ERROR] 需要 root 权限的用户运行脚本"
        exit 1
fi
}

# 检测系统
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
  else
    echo "无法检测操作系统类型"
    exit 1
  fi
}

check_mysql_version() {
  echo "[INFO] 校验 MySQL 版本号..."

  case "$MYSQL_VERSION" in
    5.5 | 5.6 | 5.7 | 8.0 | 8.1 | 8.2)
      echo "[INFO] MySQL 版本: $MYSQL_VERSION"
      ;;
    *)
      echo "[ERROR] 不支持的 MySQL 版本: $MYSQL_VERSION"
      exit 1
      ;;
  esac
}

check_compatible(){
  # 定义兼容关系
  is_compatible=false
  case "$OS_ID" in
    ubuntu | debian)
      . /etc/os-release
      UBUNTU_VERSION=${VERSION_ID//\"/} 
      echo "[INFO] 系统版本: $UBUNTU_VERSION"

      if [[ "$MYSQL_VERSION" =~ ^5\. ]]; then
        # case "$UBUNTU_VERSION" in
        #     "16.04"|"18.04"|"20.04")
        #         is_compatible=true
        #         ;;
        # esac
        is_compatible=false
      elif [[ "$MYSQL_VERSION" =~ ^8\. ]]; then
        case "$UBUNTU_VERSION" in
            "16.04"|"18.04"|"20.04"|"22.04"|"24.04")
                is_compatible=true
                ;;
        esac
      else
        echo "[ERROR] 不支持的 MySQL 版本: $MYSQL_VERSION"
        exit 1
      fi

      # 输出判断结果
      if $is_compatible; then
          echo "[INFO] Ubuntu $UBUNTU_VERSION 支持安装 MySQL $MYSQL_VERSION"
      else
          echo "[ERROR] Ubuntu $UBUNTU_VERSION 不支持安装 MySQL $MYSQL_VERSION"
          echo "[ERROR] 建议使用 Docker 方式安装，或切换至兼容版本的 Ubuntu 系统"
          exit 1
      fi
      ;;
  esac
}

# 卸载 mysql
uninstall_mysql() {
  echo "[INFO] 开始卸载已安装的MySQL..."
  case "$OS_ID" in
    ubuntu | debian)
      systemctl stop mysql || true
      apt purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* || true
      rm -rf /etc/mysql /var/lib/mysql /var/lib/mysql* /var/log/mysql* /etc/apparmor.d/usr.sbin.mysqld
      apt autoremove -y
      apt autoclean -y
      ;;
    centos | rhel)
      systemctl stop mysqld || true
      yum remove -y mysql-community-server mysql-community-client mysql-community-common mysql-community-libs mysql-community-devel mysql-community-client-plugins

      yum-config-manager --disable mysql*-Community > /dev/null 2>&1 || true
      yum repolist all | grep mysql

      rm -rf /var/lib/mysql /etc/my.cnf
      if [ -f /var/log/mysqld.log ]; then
        rm -f /var/log/mysqld.log
      fi
      ;;
    suse | sles)
      systemctl stop mysql || true
      zypper remove -y mysql-community-server
      rm -rf /var/lib/mysql /etc/my.cnf
      ;;
    *)
      echo "不支持的系统: $OS_ID"
      exit 1
      ;;
  esac
  echo "[INFO] MySQL 卸载完成"
}

# 安装 mysql
install_mysql() {
  echo "[INFO] 开始安装 MySQL $MYSQL_VERSION..."

  case "$OS_ID" in
    ubuntu | debian)
      apt-get update
      apt-get install -y wget lsb-release gnupg debconf-utils
      wget https://dev.mysql.com/get/mysql-apt-config_0.8.24-1_all.deb

      # 设置非交互版本选择
      echo "mysql-apt-config mysql-apt-config/select-server select mysql-$MYSQL_VERSION" | debconf-set-selections

      # 安装配置包（不弹窗）
      DEBIAN_FRONTEND=noninteractive dpkg -i mysql-apt-config_0.8.24-1_all.deb
      
      # 更新 apt 源
      apt-get update

      # 安装 mysql-server
      DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
      ;;
    centos | rhel)
      # rm -f /etc/pki/rpm-gpg/RPM-GPG-KEY-mysql
      # rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2023
      yum install -y expect
      yum install -y https://dev.mysql.com/get/mysql80-community-release-el7-3.noarch.rpm || true
      yum-config-manager --enable "mysql${MYSQL_VERSION/./}-community"
      yum install -y mysql-community-server  --nogpgcheck
      ;;
    suse | sles)
      zypper install -y expect
      zypper install -y https://dev.mysql.com/get/mysql80-community-release-sl15-3.noarch.rpm
      zypper refresh
      zypper install -y mysql-community-server
      ;;
    *)
      echo "[ERROR] 不支持的系统: $OS_ID"
      exit 1
      ;;
  esac

  systemctl enable mysql || systemctl enable mysqld
  systemctl start mysql || systemctl start mysqld
  echo "[INFO] MySQL 安装完成。"
}

alter_mysql_root_password() {
  if [[ "$MYSQL_VERSION" == '5.5' || "$MYSQL_VERSION" == '5.6' ]]; then
    echo "[INFO] MySQL $MYSQL_VERSION 不需要临时密码，直接修改 root 密码"
    mysqladmin -u root password "${NEW_ROOT_PASSWORD}"
    echo "[INFO] MySQL $MYSQL_VERSION root 密码修改成功为: $NEW_ROOT_PASSWORD"
    return
  fi

  # Ubuntu 上初次通过 APT 安装 MySQL 8 后，默认不会设置 root 密码，也不会生成随机密码
  case "$OS_ID" in
    ubuntu | debian)
      # 创建SQL语句文件
      SQL_FILE="/tmp/mysql_secure_install.sql"

      cat > "$SQL_FILE" <<EOF
      ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${NEW_ROOT_PASSWORD}';
      FLUSH PRIVILEGES;
EOF

      echo "[INFO] 正在使用 sudo mysql 执行 SQL 以设置 root 密码..."

      # 执行SQL
      sudo mysql < "$SQL_FILE"

      # 检查是否设置成功
      echo "[INFO] 尝试使用新密码登录 MySQL..."

      mysql -uroot -p"${NEW_ROOT_PASSWORD}" -e "SELECT VERSION();" >/dev/null 2>&1

      if [ $? -eq 0 ]; then
          echo "[SUCCESS] root 密码修改成为: $NEW_ROOT_PASSWORD"
      else
          echo "[ERROR] root 密码设置失败，请检查是否已正确安装 MySQL，或当前用户是否有 sudo 权限。"
          exit 1
      fi

      # 清理
      rm -f "$SQL_FILE"
      return
      ;;
  esac

  # 获取临时密码
  TEMP_PASSWORD=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')

  if [[ -z "$TEMP_PASSWORD" ]]; then
      echo "[ERROR] 无法获取临时密码，安装可能失败。"
      exit 1
  fi

  echo "[INFO] 获取到的临时密码为: $TEMP_PASSWORD"

  # 使用 expect 自动登录并修改密码
  yum install -y expect

  expect <<EOF
  set timeout 10
  spawn mysql -u root -p
  expect "Enter password:"
  send "$TEMP_PASSWORD\r"
  expect "mysql>"
  send "ALTER USER 'root'@'localhost' IDENTIFIED BY '${NEW_ROOT_PASSWORD}';\r"
  expect "mysql>"
  send "exit;\r"
  expect eof
EOF

  echo "[INFO] MySQL root 密码修改成功为: $NEW_ROOT_PASSWORD"

}

check_mysql_status(){
  # 等待服务启动
  sleep 5
  if systemctl is-active --quiet mysql || systemctl is-active --quiet mysqld; then
    echo "[INFO] MySQL 服务正在运行"
  else
    echo "[ERROR] MySQL 服务未运行，请检查安装和配置"
    exit 1
  fi
}

main() {
  # 验证用户权限
  check_privilege
  # 检查mysql版本
  check_mysql_version
  # 获取os信息
  detect_os
  # 检查mysql和系统的版本兼容性
  check_compatible
  # 卸载当前已安装的mysql
  uninstall_mysql
  # 安装mysql
  install_mysql
  # 检查mysql状态
  check_mysql_status
  # 修改mysql的root用户登录密码
  alter_mysql_root_password
}

main "$@"