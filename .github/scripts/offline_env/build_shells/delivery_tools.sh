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

# ubuntu 22.04 + tdgpt
docker run -itd \
            -v ./offline_pkgs:/opt/offline-env \
            -v ./prepare_offline_pkg.sh:/prepare_offline_pkg.sh \
            -v ./install.sh:/install.sh \
            -e PARENT_DIR=/opt/offline-env \
            --name offline_pkgs_builder \
            ubuntu:22.04
docker exec -ti offline_pkgs_builder bash -c 'echo "deb http://mirrors.aliyun.com/ubuntu/ jammy main" > /etc/apt/sources.list'
docker exec -ti offline_pkgs_builder apt update -y


docker exec -ti offline_pkgs_builder \
            sh -c \
            "chmod +x /prepare_offline_pkg.sh && \
            /prepare_offline_pkg.sh \
            --build \
            --system-packages=build-essential  \
            --python-version=3.10 \
            --python-packages=\"numpy==1.26.4,pandas==1.5.0,scikit-learn,outlier_utils,statsmodels,pyculiarity,pmdarima,flask,matplotlib,uwsgi,torch --index-url https://download.pytorch.org/whl/cpu,--upgrade keras,requests,taospy,transformers==4.40.0,accelerate\" \
            --pkg-label=delivery-20250528 \
            --tdgpt=true"

