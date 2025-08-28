#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

LOG_FILE="/var/log/k8s-cert-check.log"
RENEW_DAYS=30

calculate_days() {
    local cert_file=$1
    local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch=$(date +%s)
    echo $(( (expiry_epoch - current_epoch) / 86400 ))
}

get_worker_nodes() {
    local inventory_file="/Users/tianjiasong/deploy-k8s-ansible/inventory.ini"
    if [ -f "$inventory_file" ]; then
        awk '/^\[workers\]/,/^\[/ {if(!/^\[/ && !/^$/ && !/^#/) print $2}' "$inventory_file" | sed 's/ansible_host=//'
    fi
}

restart_k8s_components() {
    echo "Restarting Kubernetes components..."
    
    # Master node restart sequence
    systemctl daemon-reload
    
    # Remove and restart control plane containers
    crictl ps -a --name 'kube-apiserver|kube-controller-manager|kube-scheduler|etcd' -q | xargs -r -n1 crictl rm -f
    systemctl restart kubelet
    
    echo "Master node components restarted"
    
    # Get worker nodes and restart services
    echo "Restarting worker node services..."
    local worker_ips=$(get_worker_nodes)
    
    if [ -n "$worker_ips" ]; then
        for worker_ip in $worker_ips; do
            echo "Restarting services on worker: $worker_ip"
            ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 systex@$worker_ip "echo 'Systex123!' | sudo -S systemctl restart containerd.service && echo 'Systex123!' | sudo -S systemctl restart kubelet" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "✓ Worker $worker_ip restarted successfully"
            else
                echo "✗ Failed to restart worker $worker_ip"
            fi
        done
    else
        echo "No worker nodes found in inventory file"
    fi
    
    echo "$(date): K8s components restarted on all nodes" >> "$LOG_FILE"
}

if [ ! -d "/etc/kubernetes/pki" ]; then
    echo "Error: Not a Kubernetes master node"
    exit 1
fi

echo "K8s Certificate Status:"
need_renewal=false

for cert_file in /etc/kubernetes/pki/*.crt /etc/kubernetes/pki/etcd/*.crt; do
    if [ -f "$cert_file" ]; then
        days=$(calculate_days "$cert_file")
        cert_name=$(basename "$cert_file")
        
        printf "%-30s %3d days\n" "$cert_name" "$days"
        
        if [ $days -le $RENEW_DAYS ]; then
            need_renewal=true
        fi
    fi
done

if [ "$need_renewal" = true ]; then
    echo ""
    echo "Renewing certificates..."
    kubeadm certs renew all
    restart_k8s_components
    echo "Certificates renewed successfully"
    echo "$(date): Certificates renewed" >> "$LOG_FILE"
else
    echo "$(date): All certificates OK" >> "$LOG_FILE"
fi