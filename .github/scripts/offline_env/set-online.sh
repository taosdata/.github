#!/bin/bash
# Restore full network access by clearing all iptables restrictions
# 恢复完整网络访问，清除所有 iptables 限制

# Detect package manager family
# 检测包管理器家族
if command -v apt-get &>/dev/null; then
    PKG_FAMILY="deb"
else
    PKG_FAMILY="rpm"
fi

# Reset all chains
# 清空所有规则链
sudo iptables -F
sudo iptables -X
sudo iptables -Z

# Set default policies: accept everything
# 设置默认策略：全部允许
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# Persist the cleared rules (so they survive reboot)
# 持久化（重启后不会恢复旧的封锁规则）
if [[ "$PKG_FAMILY" == "deb" ]]; then
    sudo mkdir -p /etc/iptables
    sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
else
    sudo mkdir -p /etc/sysconfig
    sudo iptables-save | sudo tee /etc/sysconfig/iptables > /dev/null
fi

echo "Network access restored. All iptables restrictions removed."
