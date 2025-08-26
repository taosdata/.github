#!/bin/bash

set -e

# Usage: ./install_mongodb.sh <MONGO_VERSION>
# MONGO_VERSION: mongoDB的版本号，默认值为 "default"

MONGO_VERSION=${1:-"default"}  # 可改为 5.0、4.4 等
OS_ID=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')
OS_VERSION_ID=$(grep ^VERSION_ID= /etc/os-release | cut -d= -f2 | tr -d '"')

get_mongo_version(){
  if [[ "$MONGO_VERSION" == "default" ]]; then
    if [[ "$OS_ID" == "ubuntu" ]]; then
      if version_lt "$OS_VERSION_ID" "20.04"; then
        MONGO_VERSION="4.4"
      elif version_lt "$OS_VERSION_ID" "22.04"; then
        MONGO_VERSION="5.0"
      else
        MONGO_VERSION="6.0"
      fi
    elif [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" ]]; then
      if version_lt "$OS_VERSION_ID" "8"; then
        MONGO_VERSION="4.4"
      else
        MONGO_VERSION="6.0"
      fi
    else
      echo "[ERROR] Unsupported OS: $OS_ID"
      exit 1
    fi
  fi
}

remove_mongodb() {
  echo "[INFO] 卸载已安装的MongoDB..."
  if command -v mongod >/dev/null 2>&1; then
      echo "[INFO] MongoDB 已安装"
  else
      echo "[INFO] MongoDB 未安装"
      return 0
  fi

  echo "[INFO] Removing existing MongoDB installation..."
  if [[ "$OS_ID" == "ubuntu" ]]; then
    apt purge -y mongodb-org*
    rm -rf /etc/mongod.conf /var/lib/mongodb /var/log/mongodb /usr/share/keyrings/mongodb-server*.gpg
    apt autoremove -y
  elif [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" ]]; then
    yum remove -y mongodb-org*
    rm -rf /var/log/mongodb /var/lib/mongodb /etc/mongod.conf
  else
    echo "[ERROR] Unsupported OS: $OS_ID"
    exit 1
  fi
}

version_lt() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" != "$2" ]
}

check_avx_support() {
    echo "[INFO] 检查 CPU 是否支持 AVX..."
    if grep -q avx /proc/cpuinfo; then
        return 0
    else
        return 1
    fi
}

install_mongodb_ubuntu() {
  # 根据ubuntu操作系统版本更新mongodb版本
  get_mongo_version
  echo "[INFO] Installing MongoDB ${MONGO_VERSION} on Ubuntu..."

  # apt purge -y mongodb-org*
  # rm -rf /etc/mongod.conf /var/lib/mongodb /var/log/mongodb /usr/share/keyrings/mongodb-server*.gpg
  # apt autoremove -y

  curl -fsSL https://pgp.mongodb.com/server-${MONGO_VERSION}.asc | \
  gpg -o /usr/share/keyrings/mongodb-server-${MONGO_VERSION}.gpg --dearmor

  echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-${MONGO_VERSION}.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/${MONGO_VERSION} multiverse" | \
  tee /etc/apt/sources.list.d/mongodb-org-${MONGO_VERSION}.list

  apt update
  apt install -y mongodb-org

  systemctl enable mongod
  systemctl start mongod
}

install_mongodb_centos() {
  # 根据centos操作系统版本更新mongodb版本
  get_mongo_version
  echo "[INFO] Installing MongoDB ${MONGO_VERSION} on Centos..."
  
  cat <<EOF | tee /etc/yum.repos.d/mongodb-org-${MONGO_VERSION}.repo
[mongodb-org-${MONGO_VERSION}]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/${OS_VERSION_ID}/mongodb-org/${MONGO_VERSION}/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-${MONGO_VERSION}.asc
EOF

  yum install -y mongodb-org

  systemctl enable mongod
  systemctl start mongod
}

main() {
  echo "[INFO] Detecting OS: $OS_ID $OS_VERSION_ID"
  echo "[INFO] MONGO_VERSION: $MONGO_VERSION"
  if check_avx_support; then
    echo "[INFO] AVX support check passed."
  else
    echo "[INFO] AVX is not supported."
    if version_lt "$MONGO_VERSION" "5.0"; then
        echo "[WARN] AVX support is not required for MongoDB versions below 5.0. MONGO_VERSION=$MONGO_VERSION, "
    else
        echo "[ERROR] AVX support is required for MongoDB 5.0 and above. Exiting."
        exit 1
    fi
  fi

  remove_mongodb

  echo "[INFO] Starting MongoDB installation..."
  if [[ "$OS_ID" == "ubuntu" ]]; then
    install_mongodb_ubuntu
  elif [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" ]]; then
    install_mongodb_centos
  else
    echo "[ERROR] Unsupported OS: $OS_ID"
    exit 1
  fi

  echo "[INFO] MongoDB installation completed."
  mongod --version
  systemctl status mongod --no-pager
}

main "$@"