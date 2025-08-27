#!/bin/bash
set -e
# set -x

# Usage: ./install_hbase.sh <HBASE_VERSION>
# HBASE_VERSION默认：2.4.18

# 定义变量
HBASE_VERSION="${1:-2.4.18}"
HBASE_TAR="hbase-${HBASE_VERSION}-bin.tar.gz"
HBASE_URL="https://mirrors.tuna.tsinghua.edu.cn/apache/hbase/${HBASE_VERSION}/${HBASE_TAR}"
# JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
DOWNLOAD_URL="https://downloads.apache.org/hbase/${HBASE_VERSION}/${HBASE_TAR}"
# 国内镜像（可选）
MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/apache/hbase/${HBASE_VERSION}/${HBASE_TAR}"

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

install_jdk() {
    echo "[INFO] 卸载已安装 JDK"
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

    echo "[INFO] 安装 JDK 1.8.0..."
    case "$OS_ID" in
        ubuntu|debian)
            apt-get update -y
            NEEDRESTART_MODE=a apt-get -y install openjdk-8-jdk
            ;;
        centos|rhel)
            yum install -y java-1.8.0-openjdk-devel
            ;;
        opensuse-leap|sles|suse)
            zypper ar -f https://download.opensuse.org/repositories/Java:/openjdk:/8/SLE_15/ Java8
            zypper install -y java-1_8_0-openjdk-devel
            ;;
        *)
            echo "[ERROR] 不支持的系统：$OS_ID"
            exit 1
            ;;
    esac

    # 获取 Java path
    JAVA_HOME=$(dirname $(dirname $(readlink -f $(which javac))))

    # 检查 .bashrc 中是否已定义 JAVA_HOME、
    # 删除所有现有的 JAVA_HOME 和 PATH 相关配置
    sed -i '/export JAVA_HOME=/d' /etc/profile
    sed -i '/export PATH=.*JAVA_HOME/d' /etc/profile

    # 写入新的配置
    cat >> /etc/profile <<EOF
# Java Environment (Auto-generated)
export JAVA_HOME=${JAVA_HOME}
export PATH=\$PATH:\$JAVA_HOME/bin
EOF
    # 立即生效
    source /etc/profile
    echo "[INFO] 已将 JAVA_HOME 添加到 /etc/profile"
    echo "[INFO] Java is installed."
}

# 卸载 HBase
function uninstall_hbase(){
    # 停止 HBase 服务
    echo "[INFO] 停止 HBase 进程..."
    HBASE_HOME="/opt/hbase"
    if [ -d "${HBASE_HOME}" ]; then
        ${HBASE_HOME}/bin/stop-hbase.sh 2>/dev/null
    else
        echo "[WARN] 未检测到 HBase 安装目录 ${HBASE_HOME}，尝试终止残留进程..."
    fi

    # 强制杀死残留的 Java 进程（HMaster/HRegionServer）
    pkill -f "HMaster" || true
    pkill -f "HRegionServer" || true
    sleep 3  # 等待进程终止

    # 删除 HBase 安装目录
    echo "[INFO] 删除 HBase 文件..."
    rm -rf /opt/hbase-*  # 删除所有版本
    rm -rf /opt/hbase     # 删除软链接

    # 清理数据目录
    echo "[INFO] 清理数据目录..."
    rm -rf /tmp/hbase-*   # 临时文件
    rm -rf /var/log/hbase # 日志目录（默认位置）
    rm -rf /opt/data/hbase # 自定义数据目录示例

    # 从环境变量中移除 HBASE_HOME
    echo "[INFO] 更新环境变量..."
    sed -i '/export HBASE_HOME=/d' /etc/profile
    sed -i '/export PATH=\$PATH:\$HBASE_HOME\/bin/d' /etc/profile
    source /etc/profile

    # 验证卸载
    echo "[INFO] 验证卸载结果..."
    if ! jps | grep -qE 'HMaster|HRegionServer'; then
        echo "[INFO] HBase 卸载完成！"
    else
        echo "[WARN] 警告：仍有残留进程，请手动检查！"
        jps | grep -E 'HMaster|HRegionServer'
    fi
}
# 安装 HBase
function install_hbase() {
    # 下载并解压 HBase
    echo "下载 HBase ${HBASE_VERSION}..."
    if ! curl -fSL "$MIRROR_URL" -o "/tmp/$HBASE_TAR"; then
        echo "国内源下载失败，尝试使用官方内源..."
        # echo  curl -fSL "$DOWNLOAD_URL" -o "$HBASE_TAR"
        curl -fSL "$DOWNLOAD_URL" -o "/tmp/$HBASE_TAR"
    fi

    HBASE_HOME="/opt/hbase-${HBASE_VERSION}"

    echo "解压到 ${HBASE_HOME}..."
    if ! [ -d "${HBASE_HOME}" ]; then
        mkdir -p ${HBASE_HOME}
    fi

    echo tar -xzf /tmp/${HBASE_TAR} -C ${HBASE_HOME}
    tar -xzf /tmp/${HBASE_TAR} -C /opt
    # echo ${HBASE_VERSION}
    # echo ${HBASE_HOME}
    # mv ${HBASE_HOME} /opt/hbase
    # echo ln -sfn ${HBASE_HOME} /opt/hbase
    ln -sfn ${HBASE_HOME} /opt/hbase

    # 配置 HBase 环境变量
    echo "配置 HBASE_HOME..."
    cat >> /etc/profile <<EOF
export HBASE_HOME=${HBASE_HOME}
export PATH=\$PATH:\$HBASE_HOME/bin
EOF
    source /etc/profile

    # 创建 HBase 数据目录
    mkdir -p  /opt/hbase/data/{zookeeper,hbase}

    # 配置 hbase-site.xml
    echo "生成 hbase-site.xml..."
    cat > ${HBASE_HOME}/conf/hbase-site.xml <<EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
<property>
    <name>hbase.rootdir</name>
    <value>file://${HBASE_HOME}/data/hbase</value>
</property>
<property>
    <name>hbase.zookeeper.property.dataDir</name>
    <value>${HBASE_HOME}/data/zookeeper</value>
</property>
<property>
    <name>hbase.unsafe.stream.capability.enforce</name>
    <value>false</value>
</property>
<property>
    <name>hbase.cluster.distributed</name>
    <value>false</value>
</property>
</configuration>
EOF

    # 配置 regionservers（单机模式用 localhost）
    echo "localhost" > ${HBASE_HOME}/conf/regionservers

    # 设置用户权限
    chown -R $(whoami):$(whoami) ${HBASE_HOME}

    # 启动 HBase
    echo "启动 HBase..."
    ${HBASE_HOME}/bin/start-hbase.sh

    # 检查进程
    echo "检查 HBase 服务..."
    max_retries=20
    retry_interval=1
    ret_code=0

    for ((i=1; i<=$max_retries; i++)); do
        # 获取 HTTP 状态码
        ret_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:16010/master-status) || true
        
        echo "当前状态码: $ret_code"
        if [ "$ret_code" -eq "200" ]; then
            echo "HBase 启动成功！"
            echo "Web 界面：http://$(hostname -I | awk '{print $1}'):16010"
            exit 0
        else
            echo "尝试 $i/$max_retries: HBase 未就绪（状态码: $ret_code），等待 ${retry_interval} 秒后重试..."
            sleep $retry_interval
        fi
    done

    # 循环结束仍未成功
    echo "HBase 启动失败（最终状态码: $ret_code），请检查日志文件 ${HBASE_HOME}/logs/hbase-$(whoami)-master-*.log"
    exit 1
}

### 主流程
main() {
    check_privilege
    detect_os
    install_jdk
    uninstall_hbase
    install_hbase
}

main "$@"