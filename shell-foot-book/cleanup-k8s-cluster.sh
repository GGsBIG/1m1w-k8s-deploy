#!/bin/bash

# Kubernetes Cluster Cleanup Script for Ubuntu 20.04
# This script completely removes Kubernetes cluster and all related components

set -e

echo "=== Kubernetes Cluster Cleanup Script for Ubuntu 20.04 ==="
echo "WARNING: This will completely remove Kubernetes cluster and all related components!"
echo "Press Ctrl+C to cancel, or wait 10 seconds to continue..."
sleep 10

echo "Starting cleanup process..."

# Step 1: Stop Kubernetes services
echo "Step 1: Stopping Kubernetes services..."
sudo kubeadm reset -f --force 2>/dev/null || true

sudo systemctl stop kubelet 2>/dev/null || true
sudo systemctl disable kubelet 2>/dev/null || true
sudo systemctl stop docker 2>/dev/null || true
sudo systemctl disable docker 2>/dev/null || true
sudo systemctl stop containerd 2>/dev/null || true
sudo systemctl disable containerd 2>/dev/null || true

# Step 2: Clean up Kubernetes virtual network interfaces (保護主要網路連線)
echo "Step 2: Cleaning up Kubernetes virtual network interfaces..."
echo "Detecting current network configuration to preserve SSH connectivity..."

# 獲取當前 SSH 連線的網路介面和 IP
SSH_CLIENT_IP=$(echo $SSH_CLIENT | awk '{print $1}' 2>/dev/null || echo "")
SSH_CONNECTION_IP=$(echo $SSH_CONNECTION | awk '{print $3}' 2>/dev/null || echo "")
MAIN_INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | head -1 | awk '{print $5}' || echo "")
MAIN_IP=$(ip route get 8.8.8.8 2>/dev/null | head -1 | awk '{print $7}' || echo "")

echo "Protected network info:"
echo "- Main interface: $MAIN_INTERFACE"
echo "- Main IP: $MAIN_IP"
echo "- SSH client IP: $SSH_CLIENT_IP"
echo "- SSH connection IP: $SSH_CONNECTION_IP"

# 只清除 Kubernetes 相關的虛擬網路介面，避免清除主要網路
ip link show | grep -E 'cali|flannel|tunl|vxlan|docker0|cni|kube' | awk -F: '{print $2}' | while read iface; do
    iface=$(echo "$iface" | tr -d ' ')
    # 確保不清除主要網路介面
    if [ -n "$iface" ] && [ "$iface" != "$MAIN_INTERFACE" ] && [[ ! "$iface" =~ ^(eth|ens|enp|wlan|wlp)[0-9] ]]; then
        echo "Removing interface: $iface"
        sudo ip link set "$iface" down 2>/dev/null || true
        sudo ip link delete "$iface" 2>/dev/null || true
    else
        echo "Preserving interface: $iface"
    fi
done

# 額外檢查並強制移除 tunl0 介面
if ip link show tunl0 >/dev/null 2>&1; then
    echo "Force removing tunl0 interface..."
    sudo ip link set tunl0 down 2>/dev/null || true
    sudo ip link delete tunl0 2>/dev/null || true
    # 移除 ipip 內核模組確保 tunl0 不會重新出現
    sudo modprobe -r ipip 2>/dev/null || true
fi

# 只清除 Kubernetes 相關的 bridge，保留系統預設 bridge
ip link show type bridge | awk -F: '{print $2}' | grep -E 'docker0|cni|kube|cali' | while read bridge; do
    bridge=$(echo "$bridge" | tr -d ' ')
    if [ -n "$bridge" ] && [ "$bridge" != "br0" ] && [ "$bridge" != "virbr0" ]; then
        echo "Removing bridge: $bridge"
        sudo ip link set "$bridge" down 2>/dev/null || true
        sudo ip link delete "$bridge" 2>/dev/null || true
    else
        echo "Preserving bridge: $bridge"
    fi
done

# 只清除 veth 對，但要小心不要影響主要連線
echo "Cleaning up veth pairs (Kubernetes related only)..."
ip link show type veth | awk -F: '{print $2}' | while read veth; do
    veth=$(echo "$veth" | tr -d ' ')
    if [ -n "$veth" ]; then
        # 檢查這個 veth 是否與重要網路相關
        veth_info=$(ip addr show "$veth" 2>/dev/null || echo "")
        if [[ "$veth_info" != *"$SSH_CLIENT_IP"* ]] && [[ "$veth_info" != *"$SSH_CONNECTION_IP"* ]] && [[ "$veth_info" != *"$MAIN_IP"* ]]; then
            echo "Removing veth: $veth"
            sudo ip link delete "$veth" 2>/dev/null || true
        else
            echo "Preserving veth: $veth (connected to important network)"
        fi
    fi
done

# 不要清除主路由表，而是只清除 Kubernetes 相關路由
echo "Removing Kubernetes specific routes only..."
# 清除 Kubernetes 服務 IP 範圍的路由 (通常是 10.96.0.0/12)
sudo ip route del 10.96.0.0/12 2>/dev/null || true
# 清除 Pod IP 範圍的路由 (通常是 10.244.0.0/16 for flannel, 192.168.0.0/16 for calico)
sudo ip route del 10.244.0.0/16 2>/dev/null || true
sudo ip route del 192.168.0.0/16 2>/dev/null || true
# 清除路由快取但保留主路由表
sudo ip route flush cache 2>/dev/null || true

# Step 3: Unload kernel modules
echo "Step 3: Unloading kernel modules..."
sudo modprobe -r br_netfilter 2>/dev/null || true
sudo modprobe -r overlay 2>/dev/null || true
sudo modprobe -r ip_vs 2>/dev/null || true
sudo modprobe -r ip_vs_rr 2>/dev/null || true
sudo modprobe -r ip_vs_wrr 2>/dev/null || true
sudo modprobe -r ip_vs_sh 2>/dev/null || true
sudo modprobe -r nf_conntrack 2>/dev/null || true
sudo modprobe -r veth 2>/dev/null || true
sudo modprobe -r bridge 2>/dev/null || true
sudo modprobe -r xt_nat 2>/dev/null || true

# 移除 ipip 模組以徹底清除 tunl0 介面
echo "Removing ipip kernel module to eliminate tunl0 interface..."
sudo modprobe -r ipip 2>/dev/null || true

# Step 4: Remove all related directories and configurations
echo "Step 4: Removing directories and configurations..."
sudo rm -rf /etc/kubernetes/
sudo rm -rf /var/lib/kubelet/
sudo rm -rf /var/lib/etcd/
sudo rm -rf /etc/cni/
sudo rm -rf /opt/cni/
sudo rm -rf ~/.kube/
sudo rm -rf /root/.kube/

# Remove container runtime directories
sudo rm -rf /var/lib/containerd/
sudo rm -rf /etc/containerd/
sudo rm -rf /var/lib/docker/
sudo rm -rf /etc/docker/
sudo rm -rf /run/containerd/
sudo rm -rf /run/docker/

# Remove network configurations
sudo rm -rf /etc/systemd/network/10-calico.netdev 2>/dev/null || true
sudo rm -rf /etc/systemd/network/10-calico.network 2>/dev/null || true
sudo rm -rf /run/flannel/ 2>/dev/null || true
sudo rm -rf /etc/kube-flannel/ 2>/dev/null || true

# Step 5: Clear Kubernetes iptables and ipvs rules (保護 SSH 連線)
echo "Step 5: Clearing Kubernetes iptables and ipvs rules..."
echo "WARNING: Backing up current iptables rules before cleanup..."

# 備份當前 iptables 規則
sudo iptables-save > /tmp/iptables-backup-$(date +%Y%m%d-%H%M%S).rules 2>/dev/null || true

echo "Removing only Kubernetes-specific iptables rules..."
# 只移除 Kubernetes 相關的鏈，而不是清空所有規則
sudo iptables -t nat -D POSTROUTING -s 10.244.0.0/16 ! -d 10.244.0.0/16 -j MASQUERADE 2>/dev/null || true
sudo iptables -t nat -D POSTROUTING -s 10.96.0.0/12 ! -d 10.96.0.0/12 -j MASQUERADE 2>/dev/null || true
sudo iptables -t filter -D FORWARD -s 10.244.0.0/16 -j ACCEPT 2>/dev/null || true
sudo iptables -t filter -D FORWARD -d 10.244.0.0/16 -j ACCEPT 2>/dev/null || true

# 移除 Kubernetes 相關的自定義鏈
for chain in KUBE-SERVICES KUBE-EXTERNAL-SERVICES KUBE-NODEPORTS KUBE-POSTROUTING KUBE-MARK-MASQ KUBE-MARK-DROP; do
    sudo iptables -t nat -F $chain 2>/dev/null || true
    sudo iptables -t nat -X $chain 2>/dev/null || true
done

for chain in KUBE-FORWARD KUBE-SERVICES KUBE-EXTERNAL-SERVICES KUBE-NODEPORTS; do
    sudo iptables -t filter -F $chain 2>/dev/null || true
    sudo iptables -t filter -X $chain 2>/dev/null || true
done

# 清除 Docker 相關規則但保留基本連線
sudo iptables -t nat -D PREROUTING -m addrtype --dst-type LOCAL -j DOCKER 2>/dev/null || true
sudo iptables -t nat -D OUTPUT ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL -j DOCKER 2>/dev/null || true
sudo iptables -t nat -F DOCKER 2>/dev/null || true
sudo iptables -t nat -X DOCKER 2>/dev/null || true
sudo iptables -t filter -F DOCKER 2>/dev/null || true
sudo iptables -t filter -X DOCKER 2>/dev/null || true
sudo iptables -t filter -F DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
sudo iptables -t filter -X DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
sudo iptables -t filter -F DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
sudo iptables -t filter -X DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
sudo iptables -t filter -F DOCKER-USER 2>/dev/null || true
sudo iptables -t filter -X DOCKER-USER 2>/dev/null || true

# 確保基本政策允許連線（特別重要避免 SSH 斷線）
sudo iptables -P INPUT ACCEPT 2>/dev/null || true
sudo iptables -P FORWARD ACCEPT 2>/dev/null || true
sudo iptables -P OUTPUT ACCEPT 2>/dev/null || true

# 清除 ipvs 規則
echo "Clearing ipvs rules..."
sudo ipvsadm -C 2>/dev/null || true

echo "iptables cleanup completed. SSH connectivity should be preserved."

# Step 6: Uninstall all related packages
echo "Step 6: Uninstalling packages..."
# First unhold packages to allow removal
echo "Unholding Kubernetes packages..."
sudo apt-mark unhold kubeadm kubectl kubelet kubernetes-cni 2>/dev/null || true

# Remove Kubernetes packages
sudo apt-get remove -y kubeadm kubectl kubelet kubernetes-cni 2>/dev/null || true
sudo apt-get purge -y kubeadm kubectl kubelet kubernetes-cni 2>/dev/null || true

# Remove container runtime packages
echo "Unholding container runtime packages..."
sudo apt-mark unhold containerd.io docker-ce docker-ce-cli docker-compose-plugin 2>/dev/null || true
sudo apt-mark unhold containerd containerd.io 2>/dev/null || true

sudo apt-get remove -y containerd.io docker-ce docker-ce-cli docker-compose-plugin 2>/dev/null || true
sudo apt-get remove -y containerd 2>/dev/null || true
sudo apt-get remove -y podman buildah skopeo 2>/dev/null || true
sudo apt-get remove -y runc containernetworking-plugins 2>/dev/null || true
sudo apt-get purge -y containerd.io docker-ce docker-ce-cli docker-compose-plugin 2>/dev/null || true
sudo apt-get purge -y containerd 2>/dev/null || true
sudo apt-get purge -y podman buildah skopeo 2>/dev/null || true
sudo apt-get purge -y runc containernetworking-plugins 2>/dev/null || true

# Remove repository files
sudo rm -f /etc/apt/sources.list.d/kubernetes.list 2>/dev/null || true
sudo rm -f /etc/apt/sources.list.d/docker.list 2>/dev/null || true
sudo rm -f /etc/apt/keyrings/kubernetes-archive-keyring.gpg 2>/dev/null || true
sudo rm -f /etc/apt/keyrings/docker.gpg 2>/dev/null || true
sudo rm -f /usr/share/keyrings/kubernetes-archive-keyring.gpg 2>/dev/null || true

# Step 7: Clear system configurations
echo "Step 7: Clearing system configurations..."
sudo rm -rf /etc/systemd/system/kubelet.service.d/
sudo rm -rf /etc/systemd/system/docker.service.d/
sudo rm -rf /etc/systemd/system/containerd.service.d/

# Remove module loading configurations
sudo rm -f /etc/modules-load.d/k8s.conf
sudo rm -f /etc/modules-load.d/containerd.conf
sudo rm -f /etc/modules-load.d/docker.conf

# Remove sysctl configurations
sudo rm -f /etc/sysctl.d/k8s.conf
sudo rm -f /etc/sysctl.d/99-kubernetes-cri.conf

# Reload systemd
sudo systemctl daemon-reload
sudo systemctl reset-failed

# Step 8: Clear cache and temporary files
echo "Step 8: Clearing cache and temporary files..."
sudo apt-get autoremove -y 2>/dev/null || true
sudo apt-get autoclean 2>/dev/null || true
sudo apt-get clean 2>/dev/null || true

# Clear systemd logs (optional)
sudo journalctl --vacuum-time=1d 2>/dev/null || true

# Clear temporary files
sudo rm -rf /tmp/k8s-*
sudo rm -rf /tmp/calico-*
sudo rm -rf /tmp/containerd-*

# Step 9: Reset network settings carefully (保護 SSH 連線)
echo "Step 9: Resetting network settings (preserving SSH connectivity)..."
echo "WARNING: Network services restart may temporarily affect connectivity"
echo "Current SSH connection info preserved"

# 重新載入 sysctl 但不強制重啟網路服務
sudo sysctl --system 2>/dev/null || true

# 檢查網路連線狀態再決定是否重啟服務
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "Network connectivity OK, proceeding with careful service restart..."
    # 只重啟 networkd 如果它正在運行
    if systemctl is-active systemd-networkd >/dev/null 2>&1; then
        echo "Restarting systemd-networkd..."
        sudo systemctl restart systemd-networkd 2>/dev/null || true
        sleep 2
    fi
    
    # 檢查連線狀態，如果 OK 才重啟 networking
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo "Network still OK, restarting networking service..."
        sudo systemctl restart networking 2>/dev/null || true
        sleep 2
    else
        echo "Network connectivity lost after systemd-networkd restart, skipping networking restart"
    fi
else
    echo "Network connectivity already impaired, skipping network service restart"
    echo "Manual network configuration may be required"
fi

echo "Network reset completed. Checking connectivity..."
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "✓ Network connectivity verified"
else
    echo "⚠ Network connectivity issue detected. Manual intervention may be required."
    echo "Try: sudo systemctl restart networking"
fi

# Step 10: Set hostname according to inventory.ini
echo "Step 10: Setting hostname according to inventory.ini..."

# 獲取當前主機的 IP 位址
CURRENT_IP=$(ip route get 8.8.8.8 2>/dev/null | head -1 | awk '{print $7}' || echo "")
INVENTORY_FILE="inventory.ini"

if [ -f "$INVENTORY_FILE" ]; then
    echo "Found inventory.ini file, looking up hostname for IP: $CURRENT_IP"
    
    # 從 inventory.ini 查找對應的 hostname
    NEW_HOSTNAME=$(grep "ansible_host=$CURRENT_IP" "$INVENTORY_FILE" | awk '{print $1}' | head -1)
    
    if [ -n "$NEW_HOSTNAME" ]; then
        echo "Setting hostname to: $NEW_HOSTNAME"
        
        # 設定新的 hostname
        sudo hostnamectl set-hostname "$NEW_HOSTNAME"
        
        # 更新 /etc/hosts
        sudo sed -i "/127.0.1.1/d" /etc/hosts
        echo "127.0.1.1    $NEW_HOSTNAME" | sudo tee -a /etc/hosts
        
        # 驗證設定
        echo "New hostname: $(hostnamectl --static)"
        echo "Updated /etc/hosts:"
        grep "$NEW_HOSTNAME" /etc/hosts || echo "Warning: hostname not found in /etc/hosts"
        
    else
        echo "Warning: Could not find hostname for IP $CURRENT_IP in inventory.ini"
        echo "Available hosts in inventory:"
        grep "ansible_host=" "$INVENTORY_FILE" | awk '{print $1, $2}' || true
    fi
else
    echo "Warning: inventory.ini file not found in current directory"
    echo "Skipping hostname configuration"
fi

# Step 11: Verification
echo "Step 11: Verifying cleanup..."
echo "=== Checking for remaining Kubernetes processes ==="
ps aux | grep -E 'kube|docker|containerd' | grep -v grep || echo "No Kubernetes processes found"

echo "=== Checking network interfaces ==="
ip link show | grep -E 'cali|flannel|tunl|vxlan|docker|cni|kube' || echo "No Kubernetes network interfaces found"

echo "=== Checking mount points ==="
mount | grep -E 'kube|docker|containerd' || echo "No Kubernetes mount points found"

echo "=== Checking installed packages ==="
dpkg -l | grep -E 'kube|docker|containerd' || echo "No Kubernetes packages found"

echo "=== Checking iptables rules ==="
sudo iptables -L -n -v | grep -E 'kube|docker|cali' || echo "No Kubernetes iptables rules found"

echo "=== Checking loaded modules ==="
lsmod | grep -E 'br_netfilter|overlay|ip_vs|ipip' || echo "No Kubernetes modules loaded"

echo ""
echo "=== Cleanup completed! ==="
echo "All Kubernetes components have been successfully removed."
echo ""
echo "You can verify the cleanup by running:"
echo "docker version 2>/dev/null || echo 'Docker removed successfully'"
echo "kubectl version 2>/dev/null || echo 'kubectl removed successfully'"
echo "systemctl status kubelet 2>/dev/null || echo 'kubelet service removed'"
echo ""
echo "System is ready for fresh Kubernetes installation if needed."

# 佛祖保佑
echo "#                       _oo0oo_"
echo "#                      o8888888o"
echo "#                      88\" . \"88"
echo "#                      (| -_- |)"
echo "#                      0\\  =  /0"
echo "#                    ___/\\\`---\'/___"
echo "#                  .' \\\\|     |// '."
echo "#                 / \\\\|||  :  |||// \\"
echo "#                / _||||| -:- |||||- \\"
echo "#               |   | \\\\\\  -  /// |   |"
echo "#               | \\_|  ''\\---/''  |_/ |"
echo "#               \\  .-\\__  '-'  ___/-. /"
echo "#             ___'. .'  /--.--\\  \`. .'___"
echo "#          .\"\" '<  \`.___\\_<|>_/___.' >' \"\"."
echo "#         | | :  \`- \\\`.;\`\\ _ /\`;.\`/ - \` : | |"
echo "#         \\  \\ \`_.   \\_ __\\ /__ _/   .-\` /  /"
echo "#     =====\`-.____\`.___ \\_____/___.-\`___.-'====="
echo "#                       \`=---='"
echo "#"
echo "#"
echo "#     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "#"
echo "#               佛祖保佑         永無 BUG"
echo "#               佛祖保佑         永不加班"