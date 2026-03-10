#!/bin/bash

# Detect package manager family (deb = Ubuntu/Debian, rpm = CentOS/Kylin/openEuler)
# 检测包管理器家族（deb = Ubuntu/Debian，rpm = CentOS/Kylin/openEuler）
if command -v apt-get &>/dev/null; then
    PKG_FAMILY="deb"
else
    PKG_FAMILY="rpm"
fi

# Stop and disable firewalld if running.
# On openEuler/CentOS, firewalld uses nftables as backend with priority -100,
# which is processed BEFORE iptables (priority 0). If firewalld is active,
# its nftables rules silently drop traffic before our iptables rules are ever reached,
# making iptables -L look correct but traffic still blocked.
# 停止并禁用 firewalld（如果正在运行）。
# openEuler/CentOS 默认的 firewalld 以 nftables 为后端，优先级(-100)高于 iptables(0)，
# 会在 iptables 规则生效前拦截流量，导致 iptables -L 看起来正确但流量仍被丢弃。
if systemctl is-active --quiet firewalld 2>/dev/null; then
    echo "Stopping firewalld..."
    sudo systemctl stop firewalld
    sudo systemctl disable firewalld
fi

# Stop ufw if running (Ubuntu/Debian default firewall).
# 停止 ufw（Ubuntu/Debian 默认防火墙）。
if [[ "$PKG_FAMILY" == "deb" ]] && systemctl is-active --quiet ufw 2>/dev/null; then
    echo "Stopping ufw..."
    sudo ufw disable
    sudo systemctl stop ufw
    sudo systemctl disable ufw
fi

# Ensure nf_conntrack kernel module is loaded.
# nft flush ruleset would remove CT hooks that nf_conntrack depends on,
# causing ESTABLISHED/RELATED matching to silently fail — do NOT flush nftables here.
# 确保 nf_conntrack 内核模块已加载。
# 注意：不要执行 nft flush ruleset，否则会清掉 nf_conntrack 依赖的 CT hook，
# 导致 ESTABLISHED/RELATED 匹配失效，TCP 三次握手的 ACK 包被 DROP，SSH 无法建立。
sudo modprobe nf_conntrack 2>/dev/null || true
sudo modprobe nf_conntrack_ipv4 2>/dev/null || true

# Clear all existing iptables rules
# 清空所有现有规则
sudo iptables -F
sudo iptables -X
sudo iptables -Z

# Set default policies: drop all input, forward, and output traffic
# 设置默认策略：丢弃所有输入、转发和输出
# WARNING: Running this script will temporarily cut off network access.
# It should be executed from a VM/physical machine console, or via remote ssh using
# `nohup set-offline.sh &` so that the brief disconnection is not noticeable.
# 执行过程会断网，需要在虚拟机/物理机控制台执行，或者远程 ssh 后通过 nohup set-offline.sh & 执行，短暂断网感知不到
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT DROP

# Allow local loopback traffic
# 允许本地回环通信
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT

# Allow established and related connections (important to ensure LAN-initiated connections can respond)
# 允许已建立的和相关连接通过（重要，确保局域网发起的连接能正常回应）
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow LAN traffic: 192.168.0.0/16 covers the entire 192.168.x.x range
# 允许局域网通信：192.168.0.0/16 覆盖所有 192.168.x.x 网段
sudo iptables -A INPUT -s 192.168.0.0/16 -j ACCEPT
sudo iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT

# Save rules persistently (path differs by OS family)
# 持久化规则（路径因 OS 家族而异）
# - RPM (CentOS/Kylin/openEuler): /etc/sysconfig/iptables
# - DEB (Ubuntu/Debian):          /etc/iptables/rules.v4
if [[ "$PKG_FAMILY" == "deb" ]]; then
    sudo mkdir -p /etc/iptables
    sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
    echo "iptables rules saved to /etc/iptables/rules.v4"
else
    sudo mkdir -p /etc/sysconfig
    sudo iptables-save | sudo tee /etc/sysconfig/iptables > /dev/null
    echo "iptables rules saved to /etc/sysconfig/iptables"
fi