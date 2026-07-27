#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_banner() {
    echo -e "${RED}"
    echo "██╗  ██╗ █████╗ ███████╗     ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗   ██╗██████╗ "
    echo "██║ ██╔╝██╔══██╗██╔════╝    ██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║   ██║██╔══██╗"
    echo "█████╔╝ ╚█████╔╝███████╗    ██║     ██║     █████╗  ███████║██╔██╗ ██║██║   ██║██████╔╝"
    echo "██╔═██╗ ██╔══██╗╚════██║    ██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║   ██║██╔═══╝ "
    echo "██║  ██╗╚█████╔╝███████║    ╚██████╗███████╗███████╗██║  ██║██║ ╚████║╚██████╔╝██║     "
    echo "╚═╝  ╚═╝ ╚════╝ ╚══════╝     ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝     "
    echo ""
    echo "           Kubernetes Cluster Cleanup (Remove All Components)"
    echo "                          Powered by Ansible"
    echo -e "${NC}"
}

show_banner

echo "==========================================="
echo "Kubernetes Cluster Cleanup Script"
echo "Removes: kubeadm / kubelet / kubectl"
echo "         containerd / runc / CNI plugins"
echo "         all configs and iptables rules"
echo "==========================================="
echo ""
echo -e "${YELLOW}WARNING: This will completely destroy the Kubernetes cluster.${NC}"
echo -e "${YELLOW}         All data will be lost and cannot be recovered.${NC}"
echo ""
read -p "Are you sure you want to proceed? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."

if ansible-playbook -i inventory.ini playbooks/99-cleanup.yml; then
    echo ""
    echo -e "${GREEN}==========================================="
    echo "Cleanup completed successfully!"
    echo -e "===========================================${NC}"
    echo ""
    echo "The following have been removed from all nodes:"
    echo "  ✓ kubeadm / kubelet / kubectl"
    echo "  ✓ containerd + runc + CNI plugins"
    echo "  ✓ /etc/kubernetes  /var/lib/etcd"
    echo "  ✓ ~/.kube configs"
    echo "  ✓ Kubernetes apt repo + GPG key"
    echo "  ✓ iptables rules + virtual interfaces"
else
    echo ""
    echo -e "${RED}Cleanup encountered errors. Check output above.${NC}"
    exit 1
fi

# Clean up local join command file
rm -f join-command.sh
echo "  ✓ join-command.sh removed"

echo ""
echo "Nodes are now clean and ready for a fresh deployment."
echo "Run ./deploy.sh to redeploy."
