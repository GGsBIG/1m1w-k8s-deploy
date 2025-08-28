# Kubernetes Cluster Deployment (1 Master + 2 Workers)

Automated deployment of Kubernetes cluster using Ansible scripts with single master node configuration.

## Cluster Architecture

- **Master Node**: 1 node (ETTTT-m1: 10.10.7.210)
- **Worker Nodes**: 2 nodes
  - ETTTT-w1: 10.10.7.213
  - ETTTT-w2: 10.10.7.214
- **Control Plane Endpoint**: 10.10.7.210:6443 (Direct to master node)
- **No kube-vip**: Single master setup doesn't require load balancing

## Deployment Steps

### 1. Configure Inventory
```bash
# Edit the inventory file with your VM information
vim /Users/tianjiasong/deploy-k8s-ansible/1m2w/inventory.ini

# Example configuration:
[masters]
ETTTT-m1 ansible_host=10.10.7.210 hostname=ETTTT-m1

[workers]
ETTTT-w1 ansible_host=10.10.7.213 hostname=ETTTT-w1
ETTTT-w2 ansible_host=10.10.7.214 hostname=ETTTT-w2

[all:vars]
ansible_user=bbg
ansible_become_pass=1qaz@WSX
ansible_ssh_private_key_file=~/.ssh/id_rsa
```

### 2. Start Kubernetes Cluster Deployment
```bash
# Grant execution permission to deployment script
chmod +x /Users/tianjiasong/deploy-k8s-ansible/1m2w/deploy.sh

# Run full deployment
./deploy.sh
```

## Deployment Stages

### Stage 1: System Setup (01-system-setup.yml)
- Configure Taiwan timezone
- Install and configure chrony time synchronization
- Disable swap
- Load kernel modules
- Configure sysctl parameters

### Stage 2: Container Runtime (02-container-runtime.yml)
- Install containerd
- Install runc
- Install CNI plugins
- Configure containerd and crictl

### Stage 3: Kubernetes Installation (03-kubernetes-install.yml)
- Add Kubernetes APT repository
- Install kubelet, kubeadm, kubectl
- Lock package versions

### Stage 4: Cluster Initialization (04-cluster-init.yml)
- Initialize master node using kubeadm
- Generate worker join token
- Configure kubeconfig

### Stage 5: Network Setup (05-network-setup.yml)
- Deploy Calico CNI
- Wait for network components to be ready

### Stage 6: Join Worker Nodes (06-join-workers.yml)
- Worker nodes join the cluster
- Verify node status

### Stage 7: Finalize Setup (07-finalize-cluster.yml)
- Add labels to worker nodes
- Check cluster status
- Generate cluster information

## Usage

### Full Deployment
```bash
./deploy.sh
# or
./deploy.sh --full
```

### Execute Specific Stage
```bash
./deploy.sh --stage 1    # Execute stage 1
./deploy.sh --stage 5    # Execute stage 5
```

### Use site.yml to Execute All Stages
```bash
./deploy.sh --site
```

### List All Stages
```bash
./deploy.sh --list
```

### Show Help
```bash
./deploy.sh --help
```

## File Structure

```
├── inventory.ini              # Main Ansible host inventory (only file you need to edit)
├── site.yml                   # Main orchestration playbook (no kube-vip)
├── deploy.sh                  # Deployment script (modified for 1M+2W)
├── templates/
│   └── init-config.yaml.j2    # kubeadm configuration template
└── playbooks/
    ├── 01-system-setup.yml
    ├── 02-container-runtime.yml
    ├── 03-kubernetes-install.yml
    ├── 04-cluster-init.yml     # Modified: no kube-vip setup
    ├── 05-network-setup.yml    # Modified: removed kube-vip references
    ├── 06-join-workers.yml     # Renamed from 08
    └── 07-finalize-cluster.yml # Modified: no kube-vip cloud provider
```

## Prerequisites

1. **Ansible Installation**
   - macOS: `brew install ansible`
   - Linux: `sudo apt install ansible`

2. **SSH Connection**
   - Ensure SSH access to all nodes
   - Configure passwordless sudo

3. **System Requirements**
   - Ubuntu 20.04/22.04
   - Minimum 2GB RAM
   - Minimum 2 CPU cores

## Post-Deployment Operations

1. **Get kubeconfig**
   ```bash
   scp bbg@10.10.7.210:/etc/kubernetes/admin.conf ~/.kube/config
   ```

2. **Verify Cluster**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

3. **Install Additional Components**
   - Ingress Controller
   - Storage Classes
   - Monitoring (Prometheus/Grafana)
   - Logging (ELK Stack)

## Key Differences from Multi-Master Setup

- **No kube-vip**: Single master doesn't need load balancing
- **Direct Control Plane**: Uses master node IP directly (10.10.7.210:6443)
- **Simplified Stages**: Removed kube-vip setup and master join stages
- **7 Stages Total**: Reduced from 9 stages in HA setup

## Troubleshooting

- Check specific stage logs
- Re-execute failed stages
- Verify network connectivity and SSH permissions
- Ensure sufficient system resources

## Version Information

- Kubernetes: 1.32.4
- Containerd: 2.1.3
- Calico: v3.30.2
- No kube-vip (single master setup)