#!/bin/bash
# Restore full network access by clearing all iptables restrictions
# 恢复完整网络访问，清除所有 iptables 限制

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

sudo service iptables save 2>/dev/null || true

echo "Network access restored. All iptables restrictions removed."
