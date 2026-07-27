#!/usr/bin/env bash
# =============================================================================
# NKP Installation Script for Pre-Provisioned 1 Master + 1 Worker Cluster
# 適用環境：macOS Jumphost + Ubuntu 節點
# 執行位置：你的 Mac（Jumphost）
# =============================================================================

set -euo pipefail

# ─── 顏色輸出 ──────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
section() { echo -e "\n${BLUE}══════════════════════════════════════${NC}"; \
            echo -e "${BLUE}  $*${NC}"; \
            echo -e "${BLUE}══════════════════════════════════════${NC}"; }

# ─── 設定變數（依你的環境修改）─────────────────────────────────────────────
CLUSTER_NAME="${CLUSTER_NAME:-cka-k8s}"
CONTROL_PLANE_1_ADDRESS="${CONTROL_PLANE_1_ADDRESS:-10.10.7.50}"
WORKER_1_ADDRESS="${WORKER_1_ADDRESS:-10.10.7.51}"
CLUSTER_VIP="${CLUSTER_VIP:-10.10.7.50}"
CLUSTER_VIP_ETH_INTERFACE="${CLUSTER_VIP_ETH_INTERFACE:-ens3}"
SSH_USER="${SSH_USER:-bbg}"
SSH_PRIVATE_KEY_FILE="${SSH_PRIVATE_KEY_FILE:-$HOME/.ssh/id_rsa}"
SSH_PRIVATE_KEY_SECRET_NAME="${CLUSTER_NAME}-ssh-key"
K8S_VERSION="${K8S_VERSION:-v1.32.4}"
NKP_VERSION="${NKP_VERSION:-v2.16.1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUTANIX_DIR="$(dirname "$SCRIPT_DIR")"
KUBECONFIG_FILE="$HOME/${CLUSTER_NAME}.conf"

# MetalLB IP 範圍（請根據你的網路設定修改！）
METALLB_IP_RANGE="${METALLB_IP_RANGE:-10.10.7.100-10.10.7.120}"

# ─── 函數：前置檢查 ────────────────────────────────────────────────────────
check_prerequisites() {
  section "步驟 0：前置條件檢查"

  local missing=()

  # 檢查必要工具
  for cmd in nkp kubectl docker ssh; do
    if command -v "$cmd" &>/dev/null; then
      info "✅ $cmd: $(command -v $cmd)"
    else
      warn "❌ $cmd: 未找到"
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    error "缺少工具：${missing[*]}\n請先安裝後再執行此腳本。"
  fi

  # 檢查 Docker 是否運行
  if ! docker info &>/dev/null; then
    error "Docker 未運行，請先啟動 Docker Desktop。"
  fi
  info "✅ Docker 運行中"

  # 檢查 SSH 連線
  for node_ip in "$CONTROL_PLANE_1_ADDRESS" "$WORKER_1_ADDRESS"; do
    if ssh -i "$SSH_PRIVATE_KEY_FILE" \
           -o StrictHostKeyChecking=no \
           -o ConnectTimeout=5 \
           "${SSH_USER}@${node_ip}" "echo OK" &>/dev/null; then
      info "✅ SSH 連線到 $node_ip：成功"
    else
      error "SSH 連線到 $node_ip 失敗。請檢查 SSH 金鑰和使用者名稱。"
    fi
  done

  # 確認網路介面名稱
  info "檢查節點網路介面..."
  ACTUAL_IFACE=$(ssh -i "$SSH_PRIVATE_KEY_FILE" \
    -o StrictHostKeyChecking=no \
    "${SSH_USER}@${CONTROL_PLANE_1_ADDRESS}" \
    "ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if(\$i==\"dev\") print \$(i+1)}'" 2>/dev/null || echo "")

  if [ -n "$ACTUAL_IFACE" ] && [ "$ACTUAL_IFACE" != "$CLUSTER_VIP_ETH_INTERFACE" ]; then
    warn "節點主要網路介面是 '$ACTUAL_IFACE'，但設定為 '$CLUSTER_VIP_ETH_INTERFACE'"
    warn "請更新 CLUSTER_VIP_ETH_INTERFACE 變數"
    read -p "是否繼續使用 '$ACTUAL_IFACE'？[y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      CLUSTER_VIP_ETH_INTERFACE="$ACTUAL_IFACE"
    else
      error "請修改 CLUSTER_VIP_ETH_INTERFACE 後重新執行。"
    fi
  fi

  info "使用網路介面：$CLUSTER_VIP_ETH_INTERFACE"
}

# ─── 函數：建立 Bootstrap 叢集 ─────────────────────────────────────────────
create_bootstrap() {
  section "步驟 1：建立 Bootstrap 叢集（KinD on Mac）"

  if kubectl get nodes &>/dev/null 2>&1; then
    info "Bootstrap 叢集已存在，跳過建立"
    kubectl get nodes
    return
  fi

  info "建立 Bootstrap KinD 叢集..."
  nkp create bootstrap

  info "等待 Bootstrap 叢集就緒..."
  kubectl wait --for=condition=Ready nodes --all --timeout=5m

  info "Bootstrap 叢集節點："
  kubectl get nodes
}

# ─── 函數：建立 SSH Secret ─────────────────────────────────────────────────
create_ssh_secret() {
  section "步驟 2：建立 SSH Secret"

  if kubectl get secret "$SSH_PRIVATE_KEY_SECRET_NAME" &>/dev/null; then
    info "SSH Secret 已存在，跳過"
    return
  fi

  info "建立 SSH private key secret..."
  kubectl create secret generic "$SSH_PRIVATE_KEY_SECRET_NAME" \
    --from-file=ssh-privatekey="$SSH_PRIVATE_KEY_FILE"

  kubectl label secret "$SSH_PRIVATE_KEY_SECRET_NAME" \
    clusterctl.cluster.x-k8s.io/move=""

  info "SSH Secret 建立完成"
}

# ─── 函數：建立 Inventory ──────────────────────────────────────────────────
create_inventory() {
  section "步驟 3：建立 Pre-Provisioned Inventory"

  local inventory_file="${NUTANIX_DIR}/preprovisioned_inventory.yaml"

  cat > "$inventory_file" <<EOF
apiVersion: infrastructure.cluster.konvoy.d2iq.io/v1alpha1
kind: PreprovisionedInventory
metadata:
  name: ${CLUSTER_NAME}-control-plane
  namespace: default
  labels:
    cluster.x-k8s.io/cluster-name: ${CLUSTER_NAME}
    clusterctl.cluster.x-k8s.io/move: ""
spec:
  hosts:
  - address: ${CONTROL_PLANE_1_ADDRESS}
  sshConfig:
    port: 22
    user: ${SSH_USER}
    privateKeyRef:
      name: ${SSH_PRIVATE_KEY_SECRET_NAME}
      namespace: default
---
apiVersion: infrastructure.cluster.konvoy.d2iq.io/v1alpha1
kind: PreprovisionedInventory
metadata:
  name: ${CLUSTER_NAME}-md-0
  namespace: default
  labels:
    cluster.x-k8s.io/cluster-name: ${CLUSTER_NAME}
    clusterctl.cluster.x-k8s.io/move: ""
spec:
  hosts:
  - address: ${WORKER_1_ADDRESS}
  sshConfig:
    port: 22
    user: ${SSH_USER}
    privateKeyRef:
      name: ${SSH_PRIVATE_KEY_SECRET_NAME}
      namespace: default
EOF

  info "套用 Inventory..."
  kubectl apply -f "$inventory_file"
  info "Inventory 建立完成：$inventory_file"
}

# ─── 函數：部署 NKP 叢集 ───────────────────────────────────────────────────
deploy_cluster() {
  section "步驟 4：部署 NKP 叢集"

  local cluster_yaml="${NUTANIX_DIR}/${CLUSTER_NAME}-cluster.yaml"
  local inventory_file="${NUTANIX_DIR}/preprovisioned_inventory.yaml"

  info "產生叢集設定（dry-run）..."
  nkp create cluster preprovisioned \
    --cluster-name "$CLUSTER_NAME" \
    --control-plane-endpoint-host "$CLUSTER_VIP" \
    --virtual-ip-interface "$CLUSTER_VIP_ETH_INTERFACE" \
    --pre-provisioned-inventory-file="$inventory_file" \
    --ssh-private-key-file="$SSH_PRIVATE_KEY_FILE" \
    --kubernetes-version="$K8S_VERSION" \
    --control-plane-count=1 \
    --worker-count=1 \
    --dry-run --output=yaml \
    > "$cluster_yaml"

  info "叢集設定已產生：$cluster_yaml"
  info "部署叢集..."
  kubectl apply -f "$cluster_yaml"

  info "等待控制平面就緒（最多 30 分鐘）..."
  kubectl wait --for=condition=ControlPlaneReady \
    "clusters/${CLUSTER_NAME}" --timeout=30m

  info "取得叢集 kubeconfig..."
  nkp get kubeconfig -c "$CLUSTER_NAME" > "$KUBECONFIG_FILE"
  chmod 600 "$KUBECONFIG_FILE"

  info "驗證叢集節點..."
  kubectl --kubeconfig "$KUBECONFIG_FILE" wait \
    --for=condition=Ready nodes --all --timeout=15m

  info "叢集節點狀態："
  kubectl --kubeconfig "$KUBECONFIG_FILE" get nodes -o wide
}

# ─── 函數：移轉 CAPI 控制權 ────────────────────────────────────────────────
migrate_capi() {
  section "步驟 5：移轉 CAPI 控制權"

  info "在新叢集安裝 CAPI 組件..."
  nkp create capi-components --kubeconfig "$KUBECONFIG_FILE"

  info "移轉 CAPI 資源到新叢集..."
  nkp move capi-resources --to-kubeconfig "$KUBECONFIG_FILE"

  info "刪除 Bootstrap 叢集..."
  nkp delete bootstrap

  info "切換 kubectl context 到新叢集..."
  export KUBECONFIG="$KUBECONFIG_FILE"

  info "CAPI 移轉完成，驗證叢集..."
  kubectl get nodes
  kubectl get clusters -A
}

# ─── 函數：設定 MetalLB ────────────────────────────────────────────────────
configure_metallb() {
  section "步驟 6：設定 MetalLB Load Balancer"

  export KUBECONFIG="$KUBECONFIG_FILE"

  info "等待 MetalLB 就緒..."
  kubectl wait --for=condition=Ready pods \
    -n metallb-system --all --timeout=10m 2>/dev/null || true

  info "設定 IP 位址池：$METALLB_IP_RANGE"
  kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - ${METALLB_IP_RANGE}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default
EOF

  info "MetalLB 設定完成"
  kubectl get ipaddresspool -n metallb-system
}

# ─── 函數：安裝 Kommander ─────────────────────────────────────────────────
install_kommander() {
  section "步驟 7：安裝 Kommander（NKP 管理介面）"

  export KUBECONFIG="$KUBECONFIG_FILE"

  local kommander_yaml="${NUTANIX_DIR}/kommander.yaml"

  info "產生 Kommander 設定..."
  nkp install kommander --init > "$kommander_yaml"

  info "安裝 Kommander..."
  kubectl apply -f "$kommander_yaml"

  info "等待 Kommander 安裝完成（約 10-20 分鐘）..."
  kubectl -n kommander wait \
    --for=condition=Ready pods --all \
    --timeout=30m 2>/dev/null || true

  info "Kommander 安裝完成！"
  info "取得 Dashboard 資訊..."
  nkp get dashboard
}

# ─── 函數：驗證安裝 ────────────────────────────────────────────────────────
verify_installation() {
  section "步驟 8：驗證安裝"

  export KUBECONFIG="$KUBECONFIG_FILE"

  info "節點狀態："
  kubectl get nodes -o wide

  info "所有 Pod 狀態："
  kubectl get pods --all-namespaces | grep -v "Running\|Completed" || \
    echo "所有 Pod 運行正常"

  info "Kommander Pod："
  kubectl get pods -n kommander 2>/dev/null || info "Kommander 尚未安裝"

  info "Storage Class："
  kubectl get storageclass

  info "Services（LoadBalancer）："
  kubectl get svc --all-namespaces | grep LoadBalancer || echo "目前沒有 LoadBalancer 服務"

  section "安裝完成！"
  echo ""
  echo "  KUBECONFIG：$KUBECONFIG_FILE"
  echo "  存取叢集：kubectl --kubeconfig $KUBECONFIG_FILE get nodes"
  echo ""
  nkp get dashboard 2>/dev/null || true
}

# ─── 主流程 ────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo "================================================"
  echo "  NKP Installation Script"
  echo "  叢集：$CLUSTER_NAME"
  echo "  Master：$CONTROL_PLANE_1_ADDRESS"
  echo "  Worker：$WORKER_1_ADDRESS"
  echo "  K8s 版本：$K8S_VERSION"
  echo "================================================"
  echo ""

  # 解析參數
  STEP="${1:-all}"

  case "$STEP" in
    "check")    check_prerequisites ;;
    "bootstrap") check_prerequisites; create_bootstrap ;;
    "secret")   create_ssh_secret ;;
    "inventory") create_inventory ;;
    "deploy")   deploy_cluster ;;
    "migrate")  migrate_capi ;;
    "metallb")  configure_metallb ;;
    "kommander") install_kommander ;;
    "verify")   verify_installation ;;
    "all")
      check_prerequisites
      create_bootstrap
      create_ssh_secret
      create_inventory
      deploy_cluster
      migrate_capi
      configure_metallb
      install_kommander
      verify_installation
      ;;
    *)
      echo "用法：$0 [check|bootstrap|secret|inventory|deploy|migrate|metallb|kommander|verify|all]"
      echo ""
      echo "  all        - 執行完整安裝流程（預設）"
      echo "  check      - 只做前置條件檢查"
      echo "  bootstrap  - 建立 Bootstrap KinD 叢集"
      echo "  secret     - 建立 SSH Secret"
      echo "  inventory  - 建立 Pre-Provisioned Inventory"
      echo "  deploy     - 部署 NKP 叢集"
      echo "  migrate    - 移轉 CAPI 控制權"
      echo "  metallb    - 設定 MetalLB"
      echo "  kommander  - 安裝 Kommander 管理介面"
      echo "  verify     - 驗證安裝結果"
      exit 1
      ;;
  esac
}

main "$@"
