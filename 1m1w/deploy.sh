#!/bin/bash

BLUE='\033[0;34m'
NC='\033[0m'

show_banner() {
    echo -e "${BLUE}"
    echo "██╗  ██╗ █████╗ ███████╗    ██████╗ ███████╗██████╗ ██╗      ██████╗ ██╗   ██╗"
    echo "██║ ██╔╝██╔══██╗██╔════╝    ██╔══██╗██╔════╝██╔══██╗██║     ██╔═══██╗╚██╗ ██╔╝"
    echo "█████╔╝ ╚█████╔╝███████╗    ██║  ██║█████╗  ██████╔╝██║     ██║   ██║ ╚████╔╝ "
    echo "██╔═██╗ ██╔══██╗╚════██║    ██║  ██║██╔══╝  ██╔═══╝ ██║     ██║   ██║  ╚██╔╝  "
    echo "██║  ██╗╚█████╔╝███████║    ██████╔╝███████╗██║     ███████╗╚██████╔╝   ██║   "
    echo "╚═╝  ╚═╝ ╚════╝ ╚══════╝    ╚═════╝ ╚══════╝╚═╝     ╚══════╝ ╚═════╝    ╚═╝   "
    echo ""
    echo "           Kubernetes 1.33 Cluster Deployment (1 Master + 1 Workers)"
    echo "                              Powered by Ansible"
    echo -e "${NC}"
}

show_banner

echo "==========================================="
echo "Kubernetes Cluster Deployment Script"
echo "1 Master + 1 Workers (No kube-vip)"
echo "==========================================="

if ! command -v ansible-playbook &> /dev/null; then
    echo "Installing Ansible..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install ansible
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt update && sudo apt install -y ansible
    else
        echo "Please install Ansible manually for your OS"
        exit 1
    fi
fi

run_stage() {
    local stage_num=$1
    local stage_name=$2
    local playbook=$3
    
    echo ""
    echo "===========================================" 
    echo "Stage ${stage_num}: ${stage_name}"
    echo "==========================================="
    
    if ansible-playbook -i inventory.ini "${playbook}"; then
        echo "Stage ${stage_num} completed successfully"
    else
        echo "Stage ${stage_num} failed"
        exit 1
    fi
}

deploy_full() {
    echo "Starting full cluster deployment..."
    
    run_stage 0 "SSH Setup" "playbooks/00-ssh-setup.yml"
    run_stage 1 "System Setup" "playbooks/01-system-setup.yml"
    run_stage 2 "Container Runtime" "playbooks/02-container-runtime.yml"
    run_stage 3 "Kubernetes Install" "playbooks/03-kubernetes-install.yml"
    run_stage 4 "Cluster Initialization" "playbooks/04-cluster-init.yml"
    run_stage 5 "Network Setup" "playbooks/05-network-setup.yml"
    run_stage 6 "Join Workers" "playbooks/06-join-workers.yml"
    run_stage 7 "Finalize Cluster" "playbooks/07-finalize-cluster.yml"
    
    echo ""
    echo "Deployment completed successfully!"
    echo "To access the cluster, copy the kubeconfig from master node:/etc/kubernetes/admin.conf"
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help                    Show this help message"
    echo "  -f, --full                    Run full deployment (default)"
    echo "  -s, --stage <stage_number>    Run specific stage (0-7)"
    echo "  -l, --list                    List all available stages"
    echo "  --site                        Run using site.yml (all stages at once)"
    echo ""
    echo "Stages:"
    echo "  0. SSH Setup"
    echo "  1. System Setup"
    echo "  2. Container Runtime"
    echo "  3. Kubernetes Install"
    echo "  4. Cluster Initialization"
    echo "  5. Network Setup"
    echo "  6. Join Workers"
    echo "  7. Finalize Cluster"
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    -l|--list)
        echo "Available stages:"
        echo "  0. SSH Setup"
        echo "  1. System Setup"
        echo "  2. Container Runtime"  
        echo "  3. Kubernetes Install"
        echo "  4. Cluster Initialization"
        echo "  5. Network Setup"
        echo "  6. Join Workers"
        echo "  7. Finalize Cluster"
        exit 0
        ;;
    -s|--stage)
        if [[ -z "${2:-}" ]]; then
            echo "Error: Stage number required"
            usage
            exit 1
        fi
        
        case "$2" in
            0) run_stage 0 "SSH Setup" "playbooks/00-ssh-setup.yml" ;;
            1) run_stage 1 "System Setup" "playbooks/01-system-setup.yml" ;;
            2) run_stage 2 "Container Runtime" "playbooks/02-container-runtime.yml" ;;
            3) run_stage 3 "Kubernetes Install" "playbooks/03-kubernetes-install.yml" ;;
            4) run_stage 4 "Cluster Initialization" "playbooks/04-cluster-init.yml" ;;
            5) run_stage 5 "Network Setup" "playbooks/05-network-setup.yml" ;;
            6) run_stage 6 "Join Workers" "playbooks/06-join-workers.yml" ;;
            7) run_stage 7 "Finalize Cluster" "playbooks/07-finalize-cluster.yml" ;;
            *) echo "Error: Invalid stage number. Use 0-7." && exit 1 ;;
        esac
        ;;
    --site)
        echo "Running site.yml (all stages at once)..."
        ansible-playbook -i inventory.ini site.yml
        ;;
    -f|--full|"")
        deploy_full
        ;;
    *)
        echo "Error: Unknown option $1"
        usage
        exit 1
        ;;
esac

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