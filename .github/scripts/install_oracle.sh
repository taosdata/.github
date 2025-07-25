#!/bin/bash
set -e
# set -x

# Oracle 安装参数
ORACLE_VERSION="${1:-19c}"       # 传入参数：19c / 21c 等
ORACLE_FILE_NAME="${2:-LINUX.X64_193000_db_home.zip}" 
ORACLE_FILE_PATH=/tmp/oracle/$ORACLE_FILE_NAME  # Oracle 安装包路径
INSTALL_DIR=/opt/oracle_install
ORACLE_BASE=/opt/oracle
ORACLE_HOME=$ORACLE_BASE/product/$ORACLE_VERSION/dbhome_1
INVENTORY_LOC=/opt/oraInventory
ORACLE_SID=ORCL
ORACLE_USER="oracle"
ORACLE_GROUP="oinstall"
RESPONSE_FILE=""

# 检测操作系统
function detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
    else
        echo "[ERROR] 无法检测操作系统"
        exit 1
    fi
}

# 卸载旧版 Oracle（基础逻辑）
uninstall_oracle() {
    echo "[INFO] 检查并卸载旧 Oracle..."

    # 停止服务
    systemctl stop oracle* 2>/dev/null || true

    # 杀掉相关进程
    local pids=$(ps -ef | grep -iE "ora_.*|tnslsnr" | grep -v grep | awk '{print $2}')
    if [ -n "$pids" ]; then
        echo "停止进程：$pids"
        echo "$pids" | xargs kill -9 || true
    fi

    # 删除服务和监听配置
    rm -f /etc/init.d/oracle-xe* /etc/init.d/oracle* || true
    rm -f /etc/oratab /etc/oraInst.loc || true

    # 删除环境变量脚本
    rm -f /etc/profile.d/oracle.sh ~/.bash_profile_oracle_backup || true

    # 删除安装目录和数据目录
    rm -rf /opt/oracle /opt/oraInventory /u01/app/oracle /u02/oradata || true

    # 删除用户和组（若存在）
    userdel -r oracle 2>/dev/null || true
    groupdel dba 2>/dev/null || true
    groupdel oinstall 2>/dev/null || true

    echo "[INFO] 卸载完成"
}


# 安装依赖
install_dependencies() {
    echo "安装系统依赖..."
    case "$OS_ID" in
        ubuntu|debian)
            apt update
            apt install -y alien binutils gcc make sysstat libaio1 expect
            ;;
        centos|rhel)
            yum install -y binutils gcc make sysstat libaio expect
            ;;
        # opensuse-leap|sles|suse)
        #     zypper --non-interactive remove java-* || true
        #     ;;
        *)
            echo "[ERROR] 不支持的系统：$OS_ID"
            exit 1
            ;;
    esac
}

# 创建用户和目录
setup_oracle_user() {
    echo "[INFO] 创建 Oracle 用户(oracle)和 组(oinstall)..."
    getent group $ORACLE_GROUP >/dev/null || groupadd -g 54321 $ORACLE_GROUP
    getent group dba >/dev/null || groupadd -g 54322 dba
    id $ORACLE_USER >/dev/null 2>&1 || useradd -u 54321 -g $ORACLE_GROUP -G dba $ORACLE_USER
    echo "oracle" | passwd --stdin $ORACLE_USER
    usermod -aG dba oracle
    usermod -aG oinstall oracle
}

# 安装 Oracle（静默安装）
install_oracle_centos() {
    echo "[INFO] 开始安装 Oracle $ORACLE_VERSION..."

    echo "[INFO] 创建安装目录...$ORACLE_HOME $INVENTORY_LOC $ORACLE_BASE"
    rm -rf $ORACLE_HOME/*
    rm -rf $INVENTORY_LOC/*
    rm -rf $ORACLE_BASE/*
    mkdir -p $ORACLE_HOME $INVENTORY_LOC $ORACLE_BASE
    chown -R $ORACLE_USER:$ORACLE_GROUP $ORACLE_BASE $INVENTORY_LOC
    chmod -R 775 $ORACLE_BASE $INVENTORY_LOC

    echo "[INFO] 解压 Oracle 安装包到 $ORACLE_HOME..."
    # cd $ORACLE_BASE
    unzip -q $ORACLE_FILE_PATH -d $ORACLE_HOME
    chown -R $ORACLE_USER:$ORACLE_GROUP $ORACLE_HOME

    echo "[INFO] 创建响应文件..."
    echo "[INFO] 文件: $ORACLE_HOME/db_install_$ORACLE_VERSION.rsp"
    RESPONSE_FILE=$ORACLE_HOME/db_install_$ORACLE_VERSION.rsp
    cat > $RESPONSE_FILE <<EOF
oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v19.0.0
oracle.install.option=INSTALL_DB_AND_CONFIG

ORACLE_HOSTNAME=localhost
UNIX_GROUP_NAME=$ORACLE_GROUP
INVENTORY_LOCATION=$INVENTORY_LOC
ORACLE_HOME=$ORACLE_HOME
ORACLE_BASE=$ORACLE_BASE

oracle.install.db.InstallEdition=EE

oracle.install.db.OSDBA_GROUP=dba
oracle.install.db.OSOPER_GROUP=dba
oracle.install.db.OSBACKUPDBA_GROUP=dba
oracle.install.db.OSDGDBA_GROUP=dba
oracle.install.db.OSKMDBA_GROUP=dba
oracle.install.db.OSRACDBA_GROUP=dba

oracle.install.db.rootconfig.executeRootScript=true
oracle.install.db.rootconfig.configMethod=ROOT
oracle.install.db.rootconfig.sudoPath=/usr/bin/sudo

oracle.install.db.ConfigureAsContainerDB=false

oracle.install.db.config.starterdb.type=GENERAL_PURPOSE
oracle.install.db.config.starterdb.globalDBName=ORCLTEST
oracle.install.db.config.starterdb.SID=ORCLTEST
oracle.install.db.config.starterdb.characterSet=AL32UTF8

oracle.install.db.config.starterdb.memoryOption=false
oracle.install.db.config.starterdb.memoryLimit=2048

oracle.install.db.config.starterdb.password.ALL=Oracle123

oracle.install.db.config.starterdb.storageType=FILE_SYSTEM_STORAGE
oracle.install.db.config.starterdb.fileSystemStorage.dataLocation=$ORACLE_BASE/oradata
oracle.install.db.config.starterdb.fileSystemStorage.recoveryLocation=$ORACLE_BASE/fast_recovery_area

# oracle.install.db.config.starterdb.automatedBackup.enable=false
oracle.install.db.config.starterdb.installExampleSchemas=false

DECLINE_SECURITY_UPDATES=true
EOF
    chown $ORACLE_USER:$ORACLE_GROUP $RESPONSE_FILE

    case "$ORACLE_VERSION" in
        19c|21c)
            DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            echo "[INFO] 使用 expect 脚本安装 Oracle $ORACLE_VERSION..."
            echo "[INFO] $DIR/install_oracle_runInstaller.expect"
            expect $DIR/install_oracle_runInstaller.expect
            ;;
        *)
            echo "[ERROR] 当前Oracle $ORACLE_VERSION 不受支持"
            exit 1
            ;;
    esac

    

    # if [ $ORACLE_VERSION == "21c" ]; then
    #     echo "[INFO] 安装 Oracle 软件（静默）..."
    #     su - $ORACLE_USER -c "$ORACLE_HOME/runInstaller -silent -waitforcompletion -responseFile $RESPONSE_FILE -ignorePrereqFailure -ignoreInternalDriverError"

    #     echo "[INFO] 执行 root 安装脚本..."
    #     $INVENTORY_LOC/orainstRoot.sh
    #     $ORACLE_HOME/root.sh
    # elif [ $ORACLE_VERSION == "19c" ]; then
    #     DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    #     echo "[INFO] 使用 expect 脚本安装 Oracle 19c..."
    #     echo "[INFO] $DIR/install_oracle_runInstaller.expect"
    #     expect $DIR/install_oracle_runInstaller.expect
    # else
    #     echo "[ERROR] 不支持的 Oracle 版本：$ORACLE_VERSION"
    #     exit 1
    # fi
    echo "[INFO] 配置环境变量..."
    for user in root $ORACLE_USER; do
        echo "设置 ~/.bash_profile for $user"
        cat >> /home/$user/.bash_profile <<EOF
export ORACLE_BASE=$ORACLE_BASE
export ORACLE_HOME=$ORACLE_HOME
export ORACLE_SID=$ORACLE_SID
export PATH=\$ORACLE_HOME/bin:\$PATH
export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:/lib:/usr/lib
EOF
    done

    echo "[INFO] 启动 Oracle 监听器..."
    su - oracle -c "lsnrctl start"
}

init_oracle_db(){
    # === 可配置参数 ===
    echo "[INFO] 初始化 Oracle 数据库..."
    DB_NAME=ORCL
    DATAFILE_DEST=$ORACLE_BASE/oradata
    SYS_PASSWORD=Oracle123
    SYSTEM_PASSWORD=Oracle123

    # === 创建参数文件（init.ora）如果不存在 ===
    echo "[INFO] 检查并创建参数文件(init$ORACLE_SID.ora)..."
    INIT_FILE=$ORACLE_HOME/dbs/init$ORACLE_SID.ora

    if [ ! -f "$INIT_FILE" ]; then
        echo "[INFO] 创建参数文件: $INIT_FILE"
        cp $ORACLE_HOME/dbs/init.ora $INIT_FILE
        sed -i "s/^db_name=.*/db_name='$DB_NAME'/" "$INIT_FILE"
    fi

    # === 创建数据文件目录 ===
    echo "[INFO] 创建数据文件目录: $DATAFILE_DEST"
    mkdir -p "$DATAFILE_DEST"
    chown -R oracle:oinstall "$DATAFILE_DEST"

    # === 使用 DBCA 静默创建数据库 ===
    echo "[INFO] 开始使用 dbca 创建数据库 $ORACLE_SID ..."

    su - oracle -c "
dbca -silent -createDatabase \
  -templateName General_Purpose.dbc \
  -gdbname ${DB_NAME} -sid ${ORACLE_SID} \
  -responseFile NO_VALUE \
  -characterSet AL32UTF8 \
  -createAsContainerDatabase false \
  -databaseType MULTIPURPOSE \
  -automaticMemoryManagement false \
  -totalMemory 2048 \
  -emConfiguration NONE \
  -sysPassword ${SYS_PASSWORD} \
  -systemPassword ${SYSTEM_PASSWORD} \
  -datafileDestination ${DATAFILE_DEST}
"

    echo "[INFO] 数据库创建完成！"
}

check_oracle_status(){
    # 检查 ORACLE_HOME 目录
    if [ ! -d "$ORACLE_HOME" ]; then
        echo "[ERROR] ORACLE_HOME 目录不存在: $ORACLE_HOME"
        exit 1
    fi

    # 检查 sqlplus 是否存在
    if ! command -v sqlplus >/dev/null 2>&1; then
        echo "[ERROR] sqlplus 未安装或不在 PATH 中"
        exit 1
    fi

    # 检查监听器状态
    if ! lsnrctl status | grep -q "Start Date"; then
        echo "[ERROR] 监听器未运行"
        exit 1
    else
        echo "[INFO] 监听器正在运行"
    fi

    # 检查数据库是否启动
    CHECK_DB=$(echo "SELECT status FROM v\$instance;" | sqlplus / as sysdba | grep -E "OPEN|MOUNTED|STARTED")

    if [[ "$CHECK_DB" == *OPEN* ]]; then
        echo "[INFO] 数据库已启动并处于 OPEN 状态"
    else
        echo "[ERROR] 数据库未启动或无法连接"
        exit 1
    fi

    # 检查1521端口是否监听
    if ss -ltn | grep -q ":1521"; then
        echo "[INFO] 监听端口 1521 正在监听"
    else
        echo "[ERROR] 监听端口 1521 未监听"
        exit 1
    fi
}


# 主逻辑
main() {
    if [ ! -e "$ORACLE_FILE_PATH" ]; then
        echo "Oracle 安装文件不存在：$ORACLE_FILE_PATH"
        exit 1
    fi

    detect_os
    uninstall_oracle
    # install_dependencies
    # setup_oracle_user
    # install_oracle_centos
    # init_oracle_db
    # check_oracle_status

    echo "Oracle $ORACLE_VERSION 安装完成"
}

main "$@"