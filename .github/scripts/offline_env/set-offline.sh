#!/bin/bash
# 清空所有现有规则
sudo iptables -F
sudo iptables -X
sudo iptables -Z

# 设置默认策略：丢弃所有输入、转发和输出
# 执行过程会断网，需要在虚拟机/物理机控制台执行，或者远程 ssh 后通过 nohup set-offline.sh & 执行，短暂断网感知不到
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT DROP

# 允许本地回环通信
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT

# 允许已建立的和相关连接通过（重要，确保局域网发起的连接能正常回应）
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 允许局域网通信（192.168.0.0/22 包含 192.168.0-3.0/24，单独添加 192.168.100.0/24）
sudo iptables -A INPUT -s 192.168.0.0/22,192.168.100.0/24 -j ACCEPT
sudo iptables -A OUTPUT -d 192.168.0.0/22,192.168.100.0/24 -j ACCEPT

sudo service iptables save