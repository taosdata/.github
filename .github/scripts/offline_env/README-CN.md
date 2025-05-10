# 离线环境部署
由于用户环境普遍存在网络隔离情况，离线部署成为刚需。然而在传统离线安装时，软件包依赖关系复杂，手动收集易遗漏关键组件，不同操作系统（CentOS/Ubuntu等）的包管理机制和版本差异显著，本方案通过在联网环境中自动下载目标软件及其完整依赖树，构建标准化离线资源包，提供开箱即用的部署能力。

# 目录
- [离线环境部署](#离线环境部署)
- [目录](#目录)
  - [1. 使用说明](#1-使用说明)
    - [1.1 容器运行](#11-容器运行)
    - [1.2 宿主机运行](#12-宿主机运行)
  - [2. 获取安装包](#2-获取安装包)


## 1. 使用说明

### 1.1 容器运行

| 参数名称               | 描述                     | 示例              |
|-----------------------|-------------------------|-------------------|
| build                 | 脚本运行类型              | build/test        |
| system-packages       | 系统工具包                | vim/ntp           |
| python-version        | python 版本              | 3.10              |
| python-packages       | python 包                | fabric2,requests  |
| pkg-label             | tar包识别标签             | v1.0.20250510     |

1. 启动构建容器；

```bash
git clone https://github.com/taosdata/.github.git
cd .github/.github/scripts/offline_env
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -e PARENT_DIR=/opt/offline-env \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_pkgs_builder \
            ubuntu:22.04
docker exec -ti offline_pkgs_builder \
            sh -c \
            "/prepare_offline_pkg.sh \
            --build \
            --system-packages=vim,ntp \
            --python-version=3.10 \
            --python-packages=fabric2,requests \
            --pkg-label=1.0.202505081658"
```


2. 启动测试容器；

```bash
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -e PARENT_DIR=/opt/offline-env \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_env_test \
            ubuntu:22.04

docker exec -ti offline_env_test \
             sh -c \
             "/prepare_offline_pkg.sh \
             --test \
             --system-packages=vim,ntp \
             --python-version=3.10 \
             --python-packages=fabric2,requests \
             --pkg-label=1.0.202505081658"
```

### 1.2 宿主机运行

省略前面的 `docker run` 和 `docker exec` 步骤，直接运行 `sh -c` 中的脚本即可，这种方法运行成功后会在系统中安装好所有的包，要想反复测试需要手动删除已安装的包。


## 2. 获取安装包

可在以下目录获取，多次运行相同命令会覆盖上次的运行结果，运行不同命令会以预设的 pkg-label 区分
```bash
ls .github/.github/scripts/offline_env/offline_pkgs
```
