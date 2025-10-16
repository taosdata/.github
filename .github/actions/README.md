# GitHub Actions 自定义 Actions 使用文档

本目录包含了一系列用于 CI/CD 流程的自定义 GitHub Actions。这些 Actions 涵盖了标签管理、部署、监控、数据库安装等多个方面。

## 目录

- [标签管理](#标签管理)
- [构建与部署](#构建与部署)
- [配置管理](#配置管理)
- [工件管理](#工件管理)
- [Runner 管理](#runner-管理)
- [监控相关](#监控相关)
- [数据库安装](#数据库安装)
- [消息队列](#消息队列)
- [数据处理工具](#数据处理工具)
- [其他工具](#其他工具)

---

## 标签管理

### add-pr-labels
根据 PR 作者的团队和组织成员身份自动添加标签。

**输入参数：**
- `github-token` (必需): GitHub 访问令牌

**功能：**
- 为团队成员的 PR 添加对应的团队标签
- 为组织成员添加 `internal` 标签
- 为外部贡献者添加 `from community` 标签

**使用示例：**
```yaml
- uses: ./.github/actions/add-pr-labels
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### dynamic-labels
高级 Runner 选择器，支持组织和仓库级别的 Runner 管理。

**输入参数：**
- `include_labels` (必需): 必需的标签（逗号分隔）
- `required_count` (必需): 最少需要的 Runner 数量
- `exclude_labels`: 排除的标签（逗号分隔）
- `match_mode`: 匹配模式（`any` 或 `all`），默认 `all`
- `scope`: Runner 范围（`org` 或 `repo`），默认 `org`
- `target`: 组织名或仓库名，默认 `taosdata`
- `gh_token` (必需): GitHub 访问令牌

**输出：**
- `runners`: JSON 格式的选中 Runner 列表

**使用示例：**
```yaml
- uses: ./.github/actions/dynamic-labels
  id: select-runners
  with:
    include_labels: 'linux,gpu'
    required_count: '2'
    match_mode: 'all'
    gh_token: ${{ secrets.GITHUB_TOKEN }}
```

---

## 构建与部署

### build-taosx
构建并安装 taosX。

**使用示例：**
```yaml
- uses: ./.github/actions/build-taosx
```

### deploy-taostest
部署 taostest 测试框架。

**输入参数：**
- `pub_dl_url` (必需): 公共下载 URL
- `test_root`: TEST_ROOT 的父目录，默认 `$GITHUB_WORKSPACE/tests`
- `pip_source`: Pip 下载源，默认清华源

**使用示例：**
```yaml
- uses: ./.github/actions/deploy-taostest
  with:
    pub_dl_url: 'https://example.com/packages'
    test_root: '$GITHUB_WORKSPACE/tests'
```

### deploy-taostest-testng
部署 taostest 和 TestNG 框架。

**输入参数：**
- `taostest-dir` (必需): taos-test-framework 仓库的父目录
- `testng-dir` (必需): TestNG 仓库的父目录

**使用示例：**
```yaml
- uses: ./.github/actions/deploy-taostest-testng
  with:
    taostest-dir: '$RUNNER_WORKSPACE/../taos-test-framework'
    testng-dir: '$RUNNER_WORKSPACE/../TestNG'
```

### deploy-minio
使用 Docker 部署 MinIO 对象存储服务。

**输入参数：**
- `MINIO_ROOT_USER` (必需): MinIO 管理员用户名
- `MINIO_ROOT_PASSWORD` (必需): MinIO 管理员密码
- `MINIO_ACCESS_KEY` (必需): MinIO 访问密钥
- `MINIO_SECRET_KEY` (必需): MinIO 密钥

**使用示例：**
```yaml
- uses: ./.github/actions/deploy-minio
  with:
    MINIO_ROOT_USER: 'admin'
    MINIO_ROOT_PASSWORD: 'admin123456'
    MINIO_ACCESS_KEY: ${{ secrets.MINIO_ACCESS_KEY }}
    MINIO_SECRET_KEY: ${{ secrets.MINIO_SECRET_KEY }}
```

### deploy-superset
使用 Docker 部署 Apache Superset 数据可视化平台。

**输入参数：**
- `superset-version`: Superset 版本，默认 `latest`
- `superset-port`: 服务端口，默认 `8088`
- `superset-secret-key` (必需): Superset 密钥
- `database-type` (必需): 数据库类型（`postgresql` 或 `mysql`）
- `database-host` (必需): 数据库主机
- `database-port`: 数据库端口，默认 `5432`
- `database-name` (必需): 数据库名称
- `database-user` (必需): 数据库用户名
- `database-password` (必需): 数据库密码
- `redis-host` (必需): Redis 主机
- `redis-port`: Redis 端口，默认 `6379`
- `redis-password`: Redis 密码（可选）
- `redis-db`: Redis 数据库编号，默认 `1`
- `container-name`: 容器名称，默认 `superset`
- `network-name`: Docker 网络名称，默认 `superset-network`
- `admin-username`: 管理员用户名，默认 `admin`
- `admin-email`: 管理员邮箱，默认 `admin@superset.com`
- `admin-password` (必需): 管理员密码

**输出：**
- `superset-url`: Superset 访问地址
- `container-id`: 容器 ID

**使用示例：**
```yaml
- uses: ./.github/actions/deploy-superset
  with:
    superset-secret-key: ${{ secrets.SUPERSET_SECRET }}
    database-type: 'postgresql'
    database-host: 'localhost'
    database-name: 'superset'
    database-user: 'postgres'
    database-password: ${{ secrets.DB_PASSWORD }}
    redis-host: 'localhost'
    admin-password: ${{ secrets.ADMIN_PASSWORD }}
```

---

## 配置管理

### config-nginx
配置 Nginx 反向代理，支持 taosadapter、taoskeeper 和 explorer。

**输入参数：**
- `adapter_hosts` (必需): taosadapter IP 列表（逗号分隔）
- `adapter_port` (必需): taosadapter 端口
- `keeper_hosts` (必需): taoskeeper 主机列表（逗号分隔）
- `keeper_port` (必需): taoskeeper 端口
- `explorer_hosts` (必需): explorer 主机列表（逗号分隔）
- `explorer_port` (必需): taosexplorer 端口

**使用示例：**
```yaml
- uses: ./.github/actions/config-nginx
  with:
    adapter_hosts: '192.168.1.10,192.168.1.11'
    adapter_port: '6041'
    keeper_hosts: '192.168.1.20'
    keeper_port: '6043'
    explorer_hosts: '192.168.1.30'
    explorer_port: '6060'
```

### config-process-exporter-yml
从进程名称生成 Process Exporter 的 YAML 配置文件。

**输入参数：**
- `yml_file_path` (必需): YAML 文件路径
- `process_names` (必需): 要监控的进程名称（逗号分隔）

**使用示例：**
```yaml
- uses: ./.github/actions/config-process-exporter-yml
  with:
    yml_file_path: '/etc/process-exporter/config.yml'
    process_names: 'taosd,taosadapter,taoskeeper'
```

### config-prometheus-yml
配置 Prometheus 的 YAML 配置文件。

**输入参数：**
- `yml_file_path` (必需): YAML 文件路径
- `node_exporter_hosts` (必需): node exporter 主机列表（逗号分隔）
- `process_exporter_hosts` (必需): process exporter 主机列表（逗号分隔）

**使用示例：**
```yaml
- uses: ./.github/actions/config-prometheus-yml
  with:
    yml_file_path: '/etc/prometheus/prometheus.yml'
    node_exporter_hosts: '192.168.1.10,192.168.1.11'
    process_exporter_hosts: '192.168.1.10,192.168.1.11'
```

---

## 工件管理

### delete-artifacts
删除当前工作流运行的所有工件。

**输入参数：**
- `gh_token` (必需): 具有 `actions:write` 权限的 GitHub 令牌

**使用示例：**
```yaml
- uses: ./.github/actions/delete-artifacts
  with:
    gh_token: ${{ secrets.GITHUB_TOKEN }}
```

### download-artifacts
使用 GitHub CLI 下载当前工作流运行的所有工件。

**输入参数：**
- `gh_token` (必需): GitHub 访问令牌
- `download_dir` (必需): 保存工件的目录，默认 `artifacts`

**使用示例：**
```yaml
- uses: ./.github/actions/download-artifacts
  with:
    gh_token: ${{ secrets.GITHUB_TOKEN }}
    download_dir: 'artifacts'
```

### download-package
从 GitHub Packages 下载 Maven 或 NPM 包。

**输入参数：**
- `package-type` (必需): 包类型（`npm` 或 `maven`）
- `package-name` (必需): 包名称
- `github-token` (必需): 具有包访问权限的 GitHub 令牌
- `group-id`: Maven 包的 Group ID，默认 `com.taosdata.tdasset`
- `repo-name`: Maven 仓库名称，默认 `tdasset`
- `version`: 下载版本，默认 `latest`
- `backup`: 是否备份下载的包，默认 `false`
- `backup-dir`: 备份目录
- `extract`: 是否解压包，默认 `true`
- `extract-path`: 解压目标目录

**输出：**
- `package_version`: 下载的包版本

**使用示例：**
```yaml
- uses: ./.github/actions/download-package
  with:
    package-type: 'maven'
    package-name: 'my-package'
    github-token: ${{ secrets.GITHUB_TOKEN }}
    version: 'latest'
    extract: 'true'
```

---

## Runner 管理

### get-runners
智能 Runner 选择器，支持双范围（组织/仓库）。

**输入参数：**
- `include_labels` (必需): 必需的标签（逗号分隔）
- `required_count` (必需): 最少需要的 Runner 数量
- `exclude_labels`: 排除的标签（逗号分隔）
- `match_mode`: 匹配逻辑（`any` 或 `all`），默认 `all`
- `scope`: Runner 范围（`org` 或 `repo`），默认 `org`
- `target`: 组织名或仓库名，默认 `taosdata`
- `gh_token` (必需): GitHub 访问令牌

**输出：**
- `runners`: JSON 格式的选中 Runner 列表

**使用示例：**
```yaml
- uses: ./.github/actions/get-runners
  id: get-runners
  with:
    include_labels: 'linux,x64'
    required_count: '3'
    gh_token: ${{ secrets.GITHUB_TOKEN }}
```

### combine-ip-hostname
合并 IP-主机名文件到单个输出变量。

**输入参数：**
- `input-dir` (必需): 包含 IP-主机名文件的目录，默认 `ip_hostname`

**输出：**
- `combined_info`: 合并和去重后的 IP-主机名条目

**使用示例：**
```yaml
- uses: ./.github/actions/combine-ip-hostname
  id: combine
  with:
    input-dir: 'ip_hostname'
```

### upload-host-info
收集并上传主机 IP/主机名信息。

**输入参数：**
- `hosts_dirname` (必需): 主机目录名，默认 `ip-hostname`
- `role` (必需): 主机角色，默认 `runner`

**输出：**
- `hostname`: 包含 IP 和主机名的生成文件

**使用示例：**
```yaml
- uses: ./.github/actions/upload-host-info
  with:
    hosts_dirname: 'ip-hostname'
    role: 'worker'
```

### update-etc-hosts
将新的 IP-主机名条目追加到 hosts 文件。

**输入参数：**
- `entries` (必需): IP-主机名条目的多行字符串

**使用示例：**
```yaml
- uses: ./.github/actions/update-etc-hosts
  with:
    entries: |
      192.168.1.10 node1
      192.168.1.11 node2
```

---

## 监控相关

### install-grafana
安装 Grafana 并启动服务。

**使用示例：**
```yaml
- uses: ./.github/actions/install-grafana
```

### install-grafana-plugin
安装 Grafana 插件并配置数据源。

**输入参数：**
- `monitor-ip`: taosadapter IP，默认 `localhost`
- `monitor-port`: taosadapter 端口，默认 `6041`

**使用示例：**
```yaml
- uses: ./.github/actions/install-grafana-plugin
  with:
    monitor-ip: '192.168.1.10'
    monitor-port: '6041'
```

### import-grafana-dashboard
通过 Dashboard ID 导入 Grafana Dashboard。

**输入参数：**
- `grafana-url` (必需): Grafana URL，默认 `http://127.0.0.1:3000`
- `dashboard-ids` (必需): Dashboard ID 列表（逗号分隔），默认 `18180,20631`
- `dashboard-uids` (必需): Dashboard UID 列表（逗号分隔），默认 `td_ds_01,td_ds_02`

**使用示例：**
```yaml
- uses: ./.github/actions/import-grafana-dashboard
  with:
    grafana-url: 'http://127.0.0.1:3000'
    dashboard-ids: '18180,20631'
    dashboard-uids: 'td_ds_01,td_ds_02'
```

### import-process-exporter-dashboard
使用 JSON 导入 Process Exporter Dashboard。

**输入参数：**
- `grafana-url` (必需): Grafana URL，默认 `http://127.0.0.1:3000`
- `prometheus-url` (必需): Prometheus URL，默认 `http://127.0.0.1:9090`
- `username`: Grafana 用户名，默认 `admin`
- `password`: Grafana 密码，默认 `admin`
- `datasource-name`: Prometheus 数据源名称，默认 `td_processes`

**使用示例：**
```yaml
- uses: ./.github/actions/import-process-exporter-dashboard
  with:
    grafana-url: 'http://127.0.0.1:3000'
    prometheus-url: 'http://127.0.0.1:9090'
```

### install-prometheus
安装 Prometheus 并启动服务。

**使用示例：**
```yaml
- uses: ./.github/actions/install-prometheus
```

### install-node-exporter
安装 Node Exporter 并启动服务。

**使用示例：**
```yaml
- uses: ./.github/actions/install-node-exporter
```

### install-process-exporter
安装 Process Exporter 并启动服务。

**使用示例：**
```yaml
- uses: ./.github/actions/install-process-exporter
```

---

## 数据库安装

### install-mysql
安装 MySQL 并启动服务。

**输入参数：**
- `mysql_version`: MySQL 版本，默认 `8.0`

**使用示例：**
```yaml
- uses: ./.github/actions/install-mysql
  with:
    mysql_version: '8.0'
```

### install-pg
安装 PostgreSQL 并启动服务。

**输入参数：**
- `pg_version`: PostgreSQL 版本，默认 `15`

**使用示例：**
```yaml
- uses: ./.github/actions/install-pg
  with:
    pg_version: '15'
```

### install-mongodb
安装 MongoDB 并启动服务。

**输入参数：**
- `mongo_version`: MongoDB 版本，默认 `6.0`

**使用示例：**
```yaml
- uses: ./.github/actions/install-mongodb
  with:
    mongo_version: '6.0'
```

### install-mssql-server
安装 Microsoft SQL Server 并启动服务。

**输入参数：**
- `mssql_version`: SQL Server 版本（`2017`、`2019`、`2022`），默认 `2022`
- `sa_password`: SA 用户密码（至少 8 个字符），默认 `MyStr0ng!P@ssw0rd`
- `edition`: 版本编号（1=评估版，2=开发者版，3=快速版，4=Web，5=标准版，6=企业版），默认 `2`
- `install_dir`: 安装目录，默认 `/opt/mssql`
- `data_dir`: 数据目录，默认 `/var/opt/mssql/data`
- `skip_config`: 跳过配置（`true`/`false`），默认 `false`

**使用示例：**
```yaml
- uses: ./.github/actions/install-mssql-server
  with:
    mssql_version: '2022'
    sa_password: ${{ secrets.SA_PASSWORD }}
    edition: '2'
```

### install-influxdb
安装并启动特定版本的 InfluxDB。

**输入参数：**
- `influxdb_version`: InfluxDB 版本，默认 `2.7.11`
- `influxdb_port`: InfluxDB 端口，默认 `8086`
- `influxdb_data_dir`: 数据目录，默认 `/var/lib/influxdb`

**使用示例：**
```yaml
- uses: ./.github/actions/install-influxdb
  with:
    influxdb_version: '2.7.11'
    influxdb_port: '8086'
```

### install-iotdb
安装 Apache IoTDB 时序数据库并启动服务。

**输入参数：**
- `iotdb_version`: IoTDB 版本，默认 `2.0.5`
- `install_dir`: 安装目录，默认 `/opt/iotdb`
- `download_dir`: 下载目录，默认 `/tmp/iotdb-packages`
- `cluster_name`: 集群名称，默认 `defaultCluster`
- `rpc_port`: RPC 端口，默认 `6667`
- `force_install`: 强制安装（`true`/`false`），默认 `false`
- `skip_download`: 跳过下载（`true`/`false`），默认 `false`
- `action_mode`: 操作模式（`install` 或 `uninstall`），默认 `install`

**使用示例：**
```yaml
- uses: ./.github/actions/install-iotdb
  with:
    iotdb_version: '2.0.5'
    rpc_port: '6667'
```

### install-opentsdb
安装 OpenTSDB 并启动服务。

**输入参数：**
- `hbase_version`: HBase 版本，默认 `2.4.18`
- `protobuf_version`: Protobuf 版本，默认 `2.5.0`
- `opentsdb_version`: OpenTSDB 版本，默认 `2.4.1`

**使用示例：**
```yaml
- uses: ./.github/actions/install-opentsdb
  with:
    opentsdb_version: '2.4.1'
    hbase_version: '2.4.18'
```

### install-tdengine-enterprise
安装 TDengine 企业版并启动服务。

**输入参数：**
- `version` (必需): 版本号，例如 `3.3.5.1`
- `download_url` (必需): 下载 URL
- `clean`: 是否清理旧版本，默认 `false`

**使用示例：**
```yaml
- uses: ./.github/actions/install-tdengine-enterprise
  with:
    version: '3.3.5.1'
    download_url: ${{ secrets.DOWNLOAD_URL }}
    clean: 'false'
```

---

## 消息队列

### install-kafka
安装 Kafka 并启动服务。

**输入参数：**
- `kafka_version`: Kafka 版本，默认 `3.9.1`
- `deploy_model`: 部署模式（`kraft` 或 `zookeeper`），默认 `kraft`
- `server_ip`: 服务器 IP，默认 `localhost`
- `download_url`: 下载 URL，默认使用官方 Apache Kafka URL
- `backup_kafka`: 是否备份现有 Kafka，默认 `false`

**使用示例：**
```yaml
- uses: ./.github/actions/install-kafka
  with:
    kafka_version: '3.9.1'
    deploy_model: 'kraft'
    server_ip: '192.168.1.10'
```

### install-kafka-producer
安装 Kafka Producer。

**输入参数：**
- `pub_dl_url` (必需): 公共下载 URL
- `file_dir` (必需): 文件目录
- `file_name` (必需): 文件名

**使用示例：**
```yaml
- uses: ./.github/actions/install-kafka-producer
  with:
    pub_dl_url: 'https://example.com'
    file_dir: 'packages'
    file_name: 'kafka-producer.jar'
```

### install-mqtt-emq
安装 EMQ MQTT 服务器并启动服务。

**使用示例：**
```yaml
- uses: ./.github/actions/install-mqtt-emq
```

### install-mqtt-hivemq
安装 HiveMQ MQTT 服务器并启动服务。

**使用示例：**
```yaml
- uses: ./.github/actions/install-mqtt-hivemq
```

### install-mqtt-mosquitto
安装 Mosquitto MQTT 服务器并启动服务。

**使用示例：**
```yaml
- uses: ./.github/actions/install-mqtt-mosquitto
```

### install-mqtt-simulator
安装 MQTT 模拟器。

**输入参数：**
- `pub_dl_url` (必需): 公共下载 URL
- `azure_blob_url` (必需): Azure Blob URL

**使用示例：**
```yaml
- uses: ./.github/actions/install-mqtt-simulator
  with:
    pub_dl_url: ${{ secrets.PUB_DL_URL }}
    azure_blob_url: ${{ secrets.AZURE_BLOB_URL }}
```

### install-flashmq
安装 FlashMQ 并启动服务。

**使用示例：**
```yaml
- uses: ./.github/actions/install-flashmq
```

---

## 数据处理工具

### install-flink
安装并启动特定版本的 Apache Flink。

**输入参数：**
- `flink_version`: Flink 版本，默认 `1.17.2`
- `scala_version`: Scala 版本，默认 `2.12`
- `java_version`: Java 版本，默认 `11`
- `install_dir`: 安装目录，默认 `/opt/flink`
- `flink_user`: 运行 Flink 的用户，默认 `flink`

**使用示例：**
```yaml
- uses: ./.github/actions/install-flink
  with:
    flink_version: '1.17.2'
    scala_version: '2.12'
    java_version: '11'
```

### install-telegraf
安装 Telegraf 数据采集工具。

**输入参数：**
- `telegraf_version`: Telegraf 版本，默认 `latest`
- `ip` (必需): taosadapter IP
- `port`: REST 服务端口，默认 `6041`
- `db_name`: 数据库名称，默认 `telegraf`
- `username`: 登录用户名，默认 `root`
- `password`: 登录密码，默认 `taosdata`

**使用示例：**
```yaml
- uses: ./.github/actions/install-telegraf
  with:
    telegraf_version: 'latest'
    ip: '192.168.1.10'
    port: '6041'
    db_name: 'telegraf'
```

### install-jmeter
安装 Apache JMeter 性能测试工具。

**输入参数：**
- `jmeter_version`: JMeter 版本，默认 `5.6.3`
- `jdbc_version`: TDengine JDBC 驱动版本，默认 `3.6.3`

**使用示例：**
```yaml
- uses: ./.github/actions/install-jmeter
  with:
    jmeter_version: '5.6.3'
    jdbc_version: '3.6.3'
```

---

## 其他工具

### install-nginx
安装 Nginx 并启动服务。

**输入参数：**
- `nginx_port`: 监听端口，默认 `80`

**使用示例：**
```yaml
- uses: ./.github/actions/install-nginx
  with:
    nginx_port: '80'
```

### gen-taostest-env
为 taostest 环境生成 JSON 配置文件。

**输入参数：**
- `json_file` (必需): 包含 Runner 信息的 JSON 文件
- `test_root` (必需): TestNG 仓库的父目录
- `exclude_components`: 需要排除的组件，默认为空

**使用示例：**
```yaml
- uses: ./.github/actions/gen-taostest-env
  with:
    json_file: 'runners.json'
    test_root: '$RUNNER_WORKSPACE/../TestNG'
    exclude_components: 'component1,component2'
```

### ssh-keyless-login
配置 SSH 免密登录到目标主机。

**输入参数：**
- `target_hosts` (必需): 目标主机列表（逗号分隔）
- `password` (必需): SSH 登录密码

**使用示例：**
```yaml
- uses: ./.github/actions/ssh-keyless-login
  with:
    target_hosts: '192.168.1.10,192.168.1.11'
    password: ${{ secrets.SSH_PASSWORD }}
```

### start-opcua-server
安装并启动 OPC UA 服务器。

**使用示例：**
```yaml
- uses: ./.github/actions/start-opcua-server
```

### sync-repo
使用令牌认证克隆或更新 Git 仓库。

**输入参数：**
- `parent-dir` (必需): 仓库的父目录
- `repo-url` (必需): Git 仓库 URL
- `branch` (必需): 目标分支名称
- `res_app_id` (必需): GitHub App ID
- `res_app_key` (必需): GitHub App 密钥

**使用示例：**
```yaml
- uses: ./.github/actions/sync-repo
  with:
    parent-dir: '$RUNNER_WORKSPACE'
    repo-url: 'https://github.com/taosdata/TestNG.git'
    branch: 'main'
    res_app_id: ${{ secrets.APP_ID }}
    res_app_key: ${{ secrets.APP_KEY }}
```

### update-repo-variable
更新仓库变量的值。

**输入参数：**
- `github-token` (必需): 具有 repo 权限的 GitHub 令牌
- `repo-name` (必需): 仓库名称
- `variable-name` (必需): 要更新的变量名
- `variable-value` (必需): 变量的新值

**使用示例：**
```yaml
- uses: ./.github/actions/update-repo-variable
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    repo-name: 'taosdata/TDengine'
    variable-name: 'BUILD_VERSION'
    variable-value: '3.3.5.1'
```

### release-notes
从 Jira 问题生成发布说明。

**输入参数：**
- `jira-url` (必需): Jira 实例 URL
- `jira-user` (必需): Jira API 用户名
- `jira-token` (必需): Jira API 令牌
- `jql` (必需): 用于获取问题的 JQL 查询模板
- `version` (必需): 用于过滤问题的版本
- `project_name`: 项目名称，默认 `tdasset_en`

**输出：**
- `notes_b64`: Base64 编码的发布说明
- `notes`: 从 Jira 问题生成的发布说明

**使用示例：**
```yaml
- uses: ./.github/actions/release-notes
  id: release
  with:
    jira-url: 'https://jira.example.com'
    jira-user: ${{ secrets.JIRA_USER }}
    jira-token: ${{ secrets.JIRA_TOKEN }}
    jql: 'project = TD AND fixVersion = {version}'
    version: '3.3.5.1'
```