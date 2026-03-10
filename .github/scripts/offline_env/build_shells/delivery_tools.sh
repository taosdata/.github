#!/bin/bash

# centos 7.9
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -v ./install.sh:/install.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_pkgs_builder \
            centos:7
docker exec -ti offline_pkgs_builder \
            sh -c \
            "chmod +x /prepare_offline_pkg.sh && \
            /prepare_offline_pkg.sh \
            --build \
            --system-packages=gdb,valgrind,bpftrace,perf \
            --python-version="" \
            --python-packages="" \
            --pkg-label=delivery-20250522"

#ubuntu 20.04
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -v ./install.sh:/install.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_pkgs_builder \
            ubuntu:20.04
docker exec -ti offline_pkgs_builder \
            sh -c \
            "chmod +x /prepare_offline_pkg.sh && \
            /prepare_offline_pkg.sh \
            --build \
            --system-packages=gdb,valgrind,bpftrace,linux-tools-common,linux-tools-generic,linux-tools-5.4.0-202-generic,linux-cloud-tools-5.4.0-202-generic \
            --python-version="" \
            --python-packages="" \
            --pkg-label=delivery-20250522"

docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_env_test \
            ubuntu:20.04

docker exec -ti offline_env_test \
             sh -c \
             "/prepare_offline_pkg.sh \
             --test \
             --system-packages=gdb,valgrind,bpftrace,linux-tools-common,linux-tools-generic,linux-tools-5.4.0-202-generic,linux-cloud-tools-5.4.0-202-generic \
             --python-version="" \
             --python-packages="" \
             --pkg-label=delivery-20250522"

# ubuntu 22.04
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -v ./install.sh:/install.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_pkgs_builder \
            ubuntu:22.04
docker exec -ti offline_pkgs_builder \
            sh -c \
            "chmod +x /prepare_offline_pkg.sh && \
            /prepare_offline_pkg.sh \
            --build \
            --system-packages=gdb,valgrind,bpftrace,linux-tools-common,linux-tools-generic,linux-tools-5.15.0-119-generic,linux-cloud-tools-5.15.0-119-generic,libboost-regex1.74.0 \
            --python-version="" \
            --python-packages="" \
            --pkg-label=delivery-20250522"

docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_env_test \
            ubuntu:22.04

docker exec -ti offline_env_test \
             sh -c \
             "/prepare_offline_pkg.sh \
             --test \
             --system-packages=gdb,valgrind,bpftrace,linux-tools-common,linux-tools-generic,linux-tools-5.15.0-119-generic,linux-cloud-tools-5.15.0-119-generic,libboost-regex1.74.0 \
             --python-version="" \
             --python-packages="" \
             --pkg-label=delivery-20250522"


# ubuntu 24.04
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -v ./install.sh:/install.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_pkgs_builder \
            ubuntu:24.04
docker exec -ti offline_pkgs_builder \
            sh -c \
            "chmod +x /prepare_offline_pkg.sh && \
            /prepare_offline_pkg.sh \
            --build \
            --system-packages=gdb,valgrind \
            --python-version="" \
            --python-packages="" \
            --pkg-label=delivery-20250522"

docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_env_test \
            ubuntu:24.04

docker exec -ti offline_env_test \
             sh -c \
             "/prepare_offline_pkg.sh \
             --test \
             --system-packages=gdb,valgrind \
             --python-version="" \
             --python-packages="" \
             --pkg-label=delivery-20250522"


# kylin sp2
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -v ./install.sh:/install.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_pkgs_builder \
            macrosan/kylin:v10-sp2
docker exec -ti offline_pkgs_builder \
            sh -c \
            "chmod +x /prepare_offline_pkg.sh && \
            /prepare_offline_pkg.sh \
            --build \
            --system-packages=valgrind,bpftrace,perf \
            --python-version="" \
            --python-packages="" \
            --pkg-label=delivery-20250522"

docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_env_test \
            macrosan/kylin:v10-sp2

docker exec -ti offline_env_test \
             sh -c \
             "/prepare_offline_pkg.sh \
             --test \
             --system-packages=valgrind,bpftrace,perf \
             --python-version="" \
             --python-packages="" \
             --pkg-label=delivery-20250522"

# kylin sp3
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -v ./install.sh:/install.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_pkgs_builder \
            macrosan/kylin:v10-sp3-2403
docker exec -ti offline_pkgs_builder \
            sh -c \
            "chmod +x /prepare_offline_pkg.sh && \
            /prepare_offline_pkg.sh \
            --build \
            --system-packages=valgrind,bpftrace,perf \
            --python-version="" \
            --python-packages="" \
            --pkg-label=delivery-20250522"

docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_env_test \
            macrosan/kylin:v10-sp3-2403

docker exec -ti offline_env_test \
             sh -c \
             "/prepare_offline_pkg.sh \
             --test \
             --system-packages=valgrind,bpftrace,perf \
             --python-version="" \
             --python-packages="" \
             --pkg-label=delivery-20250522"

# ubuntu 20.04 + tdgpt
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -v ./install.sh:/install.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_pkgs_builder \
            ubuntu:20.04

docker exec -ti offline_pkgs_builder \
            sh -c \
            "chmod +x /prepare_offline_pkg.sh && \
            /prepare_offline_pkg.sh \
            --build \
            --system-packages=build-essential  \
            --python-version=3.10 \
            --python-packages=\"numpy==1.26.4,pandas==1.5.0,scikit-learn,outlier_utils,statsmodels,pyculiarity,pmdarima,flask,matplotlib,uwsgi,torch --index-url https://download.pytorch.org/whl/cpu,--upgrade keras,requests,taospy,transformers==4.40.0,accelerate\" \
            --pkg-label=TDgpt-20250530 \
            --tdgpt=true"


# ubuntu 22.04 + tdgpt
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -v ./install.sh:/install.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_pkgs_builder \
            ubuntu-custom:22.04
docker cp setup_env.sh offline_pkgs_builder:/root

docker exec -ti offline_pkgs_builder bash -c '/root/setup_env.sh replace_sources'

docker exec -ti offline_pkgs_builder bash -c 'apt install -y apt-offline wget curl openssh-client apt-rdepends build-essential'

docker exec -ti offline_pkgs_builder \
            sh -c \
            "chmod +x /prepare_offline_pkg.sh && \
            /prepare_offline_pkg.sh \
            --build \
            --system-packages=build-essential  \
            --python-version=3.10 \
            --python-packages=\"numpy==1.26.4,pandas==1.5.0,scikit-learn,outlier_utils,statsmodels,pyculiarity,pmdarima,flask,matplotlib,uwsgi,torch --index-url https://download.pytorch.org/whl/cpu,--upgrade keras,requests,taospy,transformers==4.40.0,accelerate\" \
            --pkg-label=TDgpt-20250530 \
            --tdgpt=true"

# ubuntu 24.04 + tdgpt
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -v ./install.sh:/install.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_pkgs_builder \
            ubuntu:24.04

docker exec -ti offline_pkgs_builder \
            sh -c \
            "chmod +x /prepare_offline_pkg.sh && \
            /prepare_offline_pkg.sh \
            --build \
            --system-packages=build-essential  \
            --python-version=3.10 \
            --python-packages=\"numpy==1.26.4,pandas==1.5.0,scikit-learn,outlier_utils,statsmodels,pyculiarity,pmdarima,flask,matplotlib,uwsgi,torch --index-url https://download.pytorch.org/whl/cpu,--upgrade keras,requests,taospy,transformers==4.40.0,accelerate\" \
            --pkg-label=TDgpt-20250530 \
            --tdgpt=true"


# centos7.9 + tdgpt
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -v ./install.sh:/install.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_pkgs_builder \
            centos:7

docker exec -ti offline_pkgs_builder \
            sh -c \
            "chmod +x /prepare_offline_pkg.sh && \
            /prepare_offline_pkg.sh \
            --build \
            --system-packages=gcc,gcc-c++ \
            --python-version=3.10 \
            --python-packages=\"numpy==1.26.4,pandas==1.5.0,scikit-learn,outlier_utils,statsmodels,pyculiarity,pmdarima,flask,matplotlib,uwsgi,torch==2.3.1+cpu --index-url https://download.pytorch.org/whl/cpu,--upgrade keras,requests,taospy,transformers==4.40.0,accelerate\" \
            --pkg-label=TDgpt-20250529 \
            --tdgpt=true"


# kylin sp2 + tdgpt
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -v ./install.sh:/install.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_pkgs_builder \
            macrosan/kylin:v10-sp2

docker exec -ti offline_pkgs_builder \
            sh -c \
            "chmod +x /prepare_offline_pkg.sh && \
            /prepare_offline_pkg.sh \
            --build \
            --system-packages=gcc,gcc-c++ \
            --python-version=3.10 \
            --python-packages=\"numpy==1.26.4,pandas==1.5.0,scikit-learn,outlier_utils,statsmodels,pyculiarity,pmdarima,flask,matplotlib,uwsgi,torch==2.3.1+cpu --index-url https://download.pytorch.org/whl/cpu,--upgrade keras,requests,taospy,transformers==4.40.0,accelerate\" \
            --pkg-label=TDgpt-20250529 \
            --tdgpt=true"

# kylin sp3 + tdgpt
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -v ./install.sh:/install.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_pkgs_builder \
            macrosan/kylin:v10-sp3-2403

docker exec -ti offline_pkgs_builder \
            sh -c \
            "chmod +x /prepare_offline_pkg.sh && \
            /prepare_offline_pkg.sh \
            --build \
            --system-packages=gcc,gcc-c++ \
            --python-version=3.10 \
            --python-packages=\"numpy==1.26.4,pandas==1.5.0,scikit-learn,outlier_utils,statsmodels,pyculiarity,pmdarima,flask,matplotlib,uwsgi,torch==2.3.1+cpu --index-url https://download.pytorch.org/whl/cpu,--upgrade keras,requests,taospy,transformers==4.40.0,accelerate\" \
            --pkg-label=TDgpt-20250529 \
            --tdgpt=true"

# openEuler 24.03-lts-sp1 + IDMP
./build_offline_pkg.sh \
    --mode=docker \
    --os=openeuler --os-ver=24.03-lts-sp1 \
    --build \
    --system-packages=tar,gzip,curl,wget,vim,fontconfig,net-tools,libXrandr,wqy-microhei-fonts,libXcomposite,htop,tzdata,libXdamage,wqy-zenhei-fonts,mesa-libgbm,unzip,at-spi2-core,libxkbcommon,poppler-utils,glibc-all-langpacks,atk,libXfixes,dbus-libs,alsa-lib,glib2,ca-certificates,at-spi2-atk \
    --python-version=3.12 \
    --idmp=true \
    --idmp-ver=1.0.13.0 \
    --gh-token=YOUR_GH_TOKEN \
    --install-java --java-version=21 \
    --pkg-label=idmp-v1.0.13.0

# openEuler 24.03-lts-sp1 + TDgpt
./build_offline_pkg.sh \
    --mode=docker \
    --os=openeuler --os-ver=24.03-lts-sp1 \
    --build \
    --system-packages=tar,gcc,gcc-c++,glibc-devel,procps-ng \
    --python-version=3.10 \
    --tdgpt=true --tdgpt-all \
    --tdengine-tsdb-vder=3.4.0.9 \
    --pip-index-url=https://pypi.tuna.tsinghua.edu.cn/simple \
    --pkg-label=tdgpt-3.4.0.9 \
     --nexus-url=https://nexus.tdengine.net


./build_offline_pkg.sh \
    --mode=docker \
    --os=openeuler --os-ver=24.03-lts-sp1 \
    --build \
    --system-packages= \
    --python-version=3.12 \
    --idmp=true \
    --idmp-ver=1.0.13.0 \
    --pip-index-url=https://pypi.tuna.tsinghua.edu.cn/simple \
    --gh-token=YOUR_GH_TOKEN \
    --install-java --java-version=21 \
    --pkg-label=idmp-v1.0.13.0 \
    --nexus-url=https://nexus.tdengine.net


# TSDB（默认，不传也行）
./build_offline_pkg.sh \
    --mode=docker \
    --os=openeuler \
    --os-ver=24.03-lts-sp1 \
    --deploy-type=tsdb \
    --pkg-label=delivery-20260310 \
    --nexus-url=https://nexus.tdengine.net

# TDgpt
./build_offline_pkg.sh \
    --mode=docker \
    --os=kylin \
    --os-ver=v10-sp3-2403 \
    --deploy-type=tdgpt \
    --tdgpt-all \
    --tdengine-tsdb-ver=3.4.0.8 \
    --python-version=3.10 \
    --pkg-label=tdgpt-3.4.0.8 \
    --nexus-url=https://nexus.tdengine.net

# IDMP
./build_offline_pkg.sh \
    --mode=docker \
    --os=openeuler \
    --os-ver=24.03-lts-sp1 \
    --deploy-type=idmp \
    --idmp-ver=1.0.13.0 \
    --gh-token=YOUR_GH_TOKEN \
    --pkg-label=idmp-1.0.13.0 \
    --nexus-url=https://nexus.tdengine.net