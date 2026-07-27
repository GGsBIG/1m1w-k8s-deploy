# NKP (Nutanix Kubernetes Platform) 完整安裝指南

## 目錄
1. [NKP 是什麼](#1-nkp-是什麼)
2. [NKP 架構解析](#2-nkp-架構解析)
3. [版本與授權說明](#3-版本與授權說明)
4. [你的 1 Master + 1 Worker 環境評估](#4-你的-1-master--1-worker-環境評估)
5. [安裝路徑選擇](#5-安裝路徑選擇)
6. [路徑 A：將現有叢集升級為 NKP 管理叢集](#6-路徑-a將現有叢集升級為-nkp-管理叢集)
7. [路徑 B：將現有叢集 Attach 到 NKP](#7-路徑-b將現有叢集-attach-到-nkp)
8. [驗證與使用](#8-驗證與使用)
9. [故障排除](#9-故障排除)

---

## 1. NKP 是什麼

NKP（Nutanix Kubernetes Platform）是 Nutanix 收購 D2iQ（前身為 Mesosphere）後推出的企業級 Kubernetes 管理平台。

### NKP 提供什麼功能？

| 功能 | 說明 |
|------|------|
| **Kommander UI** | Web-based 多叢集管理介面，統一管理所有 K8s 叢集 |
| **GitOps (FluxCD)** | 透過 Git 自動化部署應用程式 |
| **監控** | 內建 Prometheus + Grafana 監控堆疊 |
| **備份** | 內建 Velero 備份解決方案 |
| **SSO** | 支援 LDAP / SAML / OIDC / GitHub 身份驗證 |
| **RBAC** | 工作區與專案層級的細粒度存取控制 |
| **叢集生命週期** | 透過 Cluster API (CAPI) 自動化叢集建立/升級/刪除 |
| **CNI** | 支援 Cilium 和 Calico |
| **CSI** | 支援 Nutanix CSI、Rook-Ceph 等儲存驅動 |
| **政策管理** | Gatekeeper/OPA 策略執行 |

### NKP 的核心技術棧

```
┌─────────────────────────────────────────────┐
│              NKP Platform                    │
├─────────────────────────────────────────────┤
│  Kommander (管理UI)  │  Flux (GitOps)        │
│  Prometheus/Grafana  │  Velero (備份)        │
│  Gatekeeper (政策)   │  Cert-manager         │
├─────────────────────────────────────────────┤
│         Cluster API (CAPI) - 叢集生命週期     │
├─────────────────────────────────────────────┤
│     純上游 Kubernetes (kubeadm-based)        │
└─────────────────────────────────────────────┘
```

---

## 2. NKP 架構解析

### 2.1 叢集類型

NKP 有三種叢集角色：

```
┌─────────────────────────────────────────────────────────┐
│                  Bootstrap Cluster                       │
│         (臨時 KinD 叢集，在你的 Mac/Jumphost 上)          │
│    用途：僅用於初始部署，部署完成後會被刪除                  │
└──────────────────────┬──────────────────────────────────┘
                       │ 部署並轉移控制權
                       ▼
┌─────────────────────────────────────────────────────────┐
│               Management Cluster (管理叢集)               │
│           安裝了 Kommander + CAPI 的 K8s 叢集             │
│      這就是 NKP 的大腦，管理所有其他叢集                    │
└──────────────────────┬──────────────────────────────────┘
                       │ 管理
          ┌────────────┼────────────┐
          ▼            ▼            ▼
    Workload      Workload      Attached
    Cluster A     Cluster B     Cluster C
   (NKP建立)    (NKP建立)    (外部附加)
```

### 2.2 Pre-Provisioned 部署流程

```
你的 Mac (Jumphost)
    │
    │ 1. 執行 nkp create bootstrap
    │    → 建立臨時 KinD 叢集
    │
    │ 2. 執行 nkp create cluster preprovisioned
    │    → CAPI 透過 SSH 連到你的節點
    │    → 在節點上安裝 K8s
    │
    │ 3. nkp move capi-resources
    │    → 控制權從 Bootstrap 轉移到新叢集
    │
    │ 4. nkp delete bootstrap
    │    → 刪除臨時 KinD 叢集
    │
    │ 5. nkp install kommander
    │    → 安裝管理介面
    ▼
cka-k8s-m1 + cka-k8s-w1 = NKP Management Cluster
```

---

## 3. 版本與授權說明

### 版本資訊（截至 2026/02）

| 版本 | 狀態 |
|------|------|
| NKP 2.16.1 | 最新版本 |
| 支援的 K8s | 最高 1.33.x |
| 下載地址 | https://portal.nutanix.com |

> ⚠️ **重要**：NKP 目前最高支援 Kubernetes 1.33。你的叢集是 1.35.1，**存在版本不相容問題**，詳見第 4 節。

### 授權方案

| 方案 | 費用 | 說明 |
|------|------|------|
| **NKP Starter** | 免費（需 Nutanix 硬體） | 包含 Konvoy + Kommander 基礎功能 |
| **NKP Pro** | 付費 | 同一基礎設施上的管理+工作叢集 |
| **NKP Ultimate** | 付費 | 跨異構基礎設施全功能 |
| **試用授權** | 免費 30 天 | 申請地址：portal.nutanix.com |

---

## 4. 你的 1 Master + 1 Worker 環境評估

### 你的環境

```
cka-k8s-m1  10.10.7.50  Master
cka-k8s-w1  10.10.7.51  Worker
K8s 版本：1.35.1
CNI：Calico
容器執行環境：containerd 2.1.3
```

### 關鍵問題評估

| 項目 | 官方要求 | 你的環境 | 狀態 |
|------|----------|----------|------|
| 控制平面節點數 | 生產：3 個（HA） | 1 個 | ⚠️ 實驗室可行，非 HA |
| Worker 節點數 | 生產：4+ 個 | 1 個 | ⚠️ 實驗室可行 |
| K8s 版本相容性 | 最高 1.33.x | **1.35.1** | ❌ 版本過高 |
| 節點 RAM | Control: 16GB, Worker: 32GB | 未知 | 需確認 |
| 節點 CPU | Control: 4 vCPU, Worker: 8 vCPU | 未知 | 需確認 |

### ❌ 最重要的問題：Kubernetes 版本不相容

NKP 2.16.1 最高支援 K8s 1.33，而你的叢集是 **1.35.1**。

**解決方案有兩個：**

**方案 1（推薦）**：降低 K8s 版本到 1.32.x，重新部署叢集
```
k8s_version=1.32.4-1.1
k8s_image_version=v1.32.4
```

**方案 2**：不讓 NKP 管理 K8s 版本，只用 Attach Cluster 功能
- NKP 的 Attach 功能可以附加任何 CNCF 相容的 K8s 叢集
- 但部分功能（叢集升級、節點管理）會受限

---

## 5. 安裝路徑選擇

### 路徑 A：直接在你的 1+1 叢集上部署 NKP（管理叢集）

**適合場景**：你想讓這個 1+1 叢集成為 NKP 的管理平台

```
你的 Mac (Jumphost + Bootstrap 叢集)
    ↓
cka-k8s-m1 + cka-k8s-w1 → NKP Management Cluster
    ↓
(之後可以再附加或建立 Workload Clusters)
```

**優點**：完整 NKP 功能，可以透過 NKP 再管理其他叢集
**缺點**：需要重建 K8s（改版本），節點資源要求較高

→ **詳見第 6 節**

### 路徑 B：Attach 現有叢集到 NKP（工作叢集）

**適合場景**：你已有 NKP 管理叢集（或打算另外建），想把這個叢集附加進去

```
NKP Management Cluster (另一台機器)
    ↓ 透過 Kommander Attach
cka-k8s-m1 + cka-k8s-w1 → Workload/Attached Cluster
```

**優點**：不需要改動現有叢集太多
**缺點**：需要額外的機器來跑 NKP 管理叢集

→ **詳見第 7 節**

---

## 6. 路徑 A：將現有叢集升級為 NKP 管理叢集

> 這條路徑會用 NKP 重新建立 Kubernetes，取代現有的 kubeadm 叢集。

### 6.1 前置準備

#### 步驟 1：你的 Mac 上安裝必要工具

```bash
# 安裝 Docker Desktop（如果還沒有）
# 從 https://www.docker.com/products/docker-desktop/ 下載

# 安裝 kubectl
brew install kubectl

# 安裝 helm
brew install helm

# 安裝 k9s（可選，但非常好用）
brew install k9s
```

#### 步驟 2：下載 NKP CLI

1. 前往 https://portal.nutanix.com
2. 登入帳號（沒有就免費註冊）
3. 搜尋 "NKP" 下載最新版本的 `nkp_darwin_amd64` 或 `nkp_darwin_arm64`（Apple Silicon）

```bash
# 假設下載到 ~/Downloads/nkp_v2.16.1_darwin_arm64.tar.gz
cd ~/Downloads
tar zxvf nkp_v2.16.1_darwin_arm64.tar.gz
chmod +x nkp
sudo mv nkp /usr/local/bin/

# 驗證安裝
nkp version
```

#### 步驟 3：準備 SSH 金鑰

```bash
# 確認你有 SSH 金鑰可以連到兩個節點
ssh bbg@10.10.7.50 "echo 'SSH OK'"
ssh bbg@10.10.7.51 "echo 'SSH OK'"
```

#### 步驟 4：在節點上執行前置準備 Playbook

詳見 `playbooks/node-prep.yml`：
```bash
cd /Users/tianjiasong/1m1w-k8s-deploy
ansible-playbook -i inventory.ini nutanix/playbooks/node-prep.yml
```

### 6.2 修改 inventory.ini 回到相容版本

> 因為 NKP 最高支援 K8s 1.33，先把版本改回 1.32.4：

在 `inventory.ini` 修改：
```ini
k8s_version=1.32.4-1.1
k8s_image_version=v1.32.4
```

然後清理並重裝 K8s（NKP 會自己管理 K8s 安裝）：
```bash
# 在兩個節點上重置 K8s
ansible -i inventory.ini k8s_nodes -m shell -a "kubeadm reset -f" --become

# 移除舊的 K8s 套件（NKP 會自己安裝）
ansible -i inventory.ini k8s_nodes -m apt \
  -a "name=kubelet,kubeadm,kubectl state=absent purge=yes" --become
```

### 6.3 建立 Bootstrap 叢集

```bash
# 在你的 Mac 上執行
# 這會在你的 Mac 上用 Docker 建立一個臨時的 KinD K8s 叢集
nkp create bootstrap

# 驗證 bootstrap 叢集
kubectl get nodes
```

### 6.4 設定環境變數

```bash
export CLUSTER_NAME="cka-k8s"
export CLUSTER_VIP="10.10.7.50"          # 控制平面 VIP（用 master IP）
export CLUSTER_VIP_ETH_INTERFACE="ens3"  # 節點網路介面名稱（需確認）
export CONTROL_PLANE_1_ADDRESS="10.10.7.50"
export WORKER_1_ADDRESS="10.10.7.51"
export SSH_USER="bbg"
export SSH_PRIVATE_KEY_FILE="$HOME/.ssh/id_rsa"
export SSH_PRIVATE_KEY_SECRET_NAME="${CLUSTER_NAME}-ssh-key"
```

> **確認網路介面名稱**：
> ```bash
> ssh bbg@10.10.7.50 "ip link show | grep -E '^[0-9]+:' | awk '{print \$2}'"
> ```

### 6.5 建立 Pre-Provisioned Inventory

建立 `nutanix/preprovisioned_inventory.yaml`：

```bash
cat > /Users/tianjiasong/1m1w-k8s-deploy/nutanix/preprovisioned_inventory.yaml << EOF
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
```

### 6.6 建立 SSH Secret

```bash
# 在 Bootstrap 叢集中建立 SSH secret
kubectl create secret generic ${SSH_PRIVATE_KEY_SECRET_NAME} \
  --from-file=ssh-privatekey="${SSH_PRIVATE_KEY_FILE}"

kubectl label secret ${SSH_PRIVATE_KEY_SECRET_NAME} \
  clusterctl.cluster.x-k8s.io/move=""

# 套用 inventory
kubectl apply -f /Users/tianjiasong/1m1w-k8s-deploy/nutanix/preprovisioned_inventory.yaml
```

### 6.7 產生並部署 NKP 叢集設定

```bash
# 產生叢集設定（dry-run 先預覽）
nkp create cluster preprovisioned \
  --cluster-name ${CLUSTER_NAME} \
  --control-plane-endpoint-host ${CLUSTER_VIP} \
  --virtual-ip-interface ${CLUSTER_VIP_ETH_INTERFACE} \
  --pre-provisioned-inventory-file=/Users/tianjiasong/1m1w-k8s-deploy/nutanix/preprovisioned_inventory.yaml \
  --ssh-private-key-file=${SSH_PRIVATE_KEY_FILE} \
  --kubernetes-version=v1.32.4 \
  --control-plane-count=1 \
  --worker-count=1 \
  --dry-run --output=yaml \
  > /Users/tianjiasong/1m1w-k8s-deploy/nutanix/${CLUSTER_NAME}-cluster.yaml

# 檢查產生的設定
cat /Users/tianjiasong/1m1w-k8s-deploy/nutanix/${CLUSTER_NAME}-cluster.yaml

# 部署叢集
kubectl apply -f /Users/tianjiasong/1m1w-k8s-deploy/nutanix/${CLUSTER_NAME}-cluster.yaml
```

### 6.8 監控部署進度

```bash
# 方法1：NKP describe
watch nkp describe cluster -c ${CLUSTER_NAME}

# 方法2：K9s 圖形介面（推薦）
k9s

# 方法3：等待控制平面就緒
kubectl wait --for=condition=ControlPlaneReady \
  "clusters/${CLUSTER_NAME}" --timeout=30m

# 取得新叢集的 kubeconfig
nkp get kubeconfig -c ${CLUSTER_NAME} > ~/cka-k8s.conf

# 驗證節點
kubectl --kubeconfig ~/cka-k8s.conf get nodes -o wide
```

### 6.9 移轉 CAPI 控制權

```bash
# 在新叢集建立 CAPI 組件
nkp create capi-components --kubeconfig ~/cka-k8s.conf

# 將 CAPI 資源從 Bootstrap 移到新叢集
nkp move capi-resources --to-kubeconfig ~/cka-k8s.conf

# 刪除 Bootstrap 叢集
nkp delete bootstrap

# 切換 kubectl 到新叢集
export KUBECONFIG=~/cka-k8s.conf
kubectl get nodes
```

### 6.10 設定 MetalLB Load Balancer

> MetalLB 提供 K8s 在 bare-metal 環境的 LoadBalancer 服務。
> 設定一個你網路中未使用的 IP 範圍給 MetalLB 使用：

```bash
# 確認 metallb 已安裝
kubectl get pods -n metallb-system

# 設定 IP 池（根據你的網路調整）
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - 10.10.7.100-10.10.7.120
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
```

### 6.11 安裝 Kommander（管理 UI）

```bash
# 初始化 Kommander 設定
nkp install kommander --init > kommander.yaml

# 檢視設定
cat kommander.yaml

# 安裝 Kommander
kubectl apply -f kommander.yaml

# 等待安裝完成（約 10-20 分鐘）
kubectl -n kommander wait --for=condition=Ready pods --all --timeout=30m

# 取得 Kommander Dashboard 連結與登入資訊
nkp get dashboard
```

---

## 7. 路徑 B：將現有叢集 Attach 到 NKP

> 這個路徑適合你已經有一個 NKP 管理叢集，想把你的 1+1 叢集附加進去作為工作叢集。

### 7.1 前提條件

- 你有一個運行中的 NKP 管理叢集（Kommander 已安裝）
- 你的叢集可以被 NKP 管理叢集的 API 存取
- 你的現有叢集有效的 kubeconfig

### 7.2 透過 Kommander UI Attach

1. 登入 Kommander Dashboard
2. 點擊左側 **"Clusters"**
3. 點擊 **"Attach Cluster"**
4. 輸入你的叢集名稱
5. 複製顯示的 kubectl apply 指令
6. 在你的叢集上執行該指令

### 7.3 透過 NKP CLI Attach

```bash
# 確認你的 kubeconfig 可以存取叢集
export KUBECONFIG=~/.kube/config
kubectl get nodes

# 在 NKP 管理叢集執行 attach
nkp attach cluster \
  --cluster-name cka-k8s \
  --kubeconfig ~/.kube/config \
  --context <your-cluster-context>
```

### 7.4 Attach 後可用的功能

| 功能 | Attach 叢集 | NKP 管理叢集 |
|------|------------|-------------|
| Kommander UI 監控 | ✅ | ✅ |
| GitOps (Flux) 應用部署 | ✅ | ✅ |
| 集中式 RBAC | ✅ | ✅ |
| 監控儀表板 | ✅ | ✅ |
| 叢集升級（透過 NKP） | ❌ | ✅ |
| 節點擴容（透過 NKP） | ❌ | ✅ |
| CAPI 叢集生命週期管理 | ❌ | ✅ |

---

## 8. 驗證與使用

### 8.1 驗證叢集狀態

```bash
# 節點狀態
kubectl get nodes -o wide

# 所有系統 Pod
kubectl get pods --all-namespaces

# NKP 相關組件
kubectl get pods -n kommander
kubectl get pods -n cert-manager
kubectl get pods -n metallb-system
kubectl get pods -n velero
```

### 8.2 存取 Kommander Dashboard

```bash
# 取得 Dashboard URL 和登入資訊
nkp get dashboard

# 輸出範例：
# Dashboard URL: https://10.10.7.100/dkp/kommander/dashboard
# Username: admin
# Password: <generated-password>
```

### 8.3 使用 Kommander 部署應用

1. 登入 Kommander Dashboard
2. 選擇 **"Applications"**
3. 從 Catalog 選擇應用（Prometheus、Grafana、Istio 等）
4. 點擊 **"Deploy"**，選擇目標叢集
5. 設定參數後確認部署

### 8.4 GitOps 工作流程

```bash
# 建立 Flux GitRepository
kubectl apply -f - <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: my-app
  namespace: kommander
spec:
  interval: 5m
  url: https://github.com/your-org/your-repo
  ref:
    branch: main
EOF
```

---

## 9. 故障排除

### 問題：Bootstrap 叢集建立失敗

```bash
# 確認 Docker 運行中
docker info

# 清理並重試
nkp delete bootstrap
docker system prune -f
nkp create bootstrap
```

### 問題：SSH 連線失敗

```bash
# 測試 SSH 連線
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no bbg@10.10.7.50

# 確認 SSH key 在節點上
ssh bbg@10.10.7.50 "cat ~/.ssh/authorized_keys"
```

### 問題：節點不 Ready

```bash
# 查看節點事件
kubectl describe node cka-k8s-m1

# 查看 CAPI 機器狀態
kubectl get machines -A
kubectl describe machine <machine-name> -n default
```

### 問題：Kommander Pod 起不來

```bash
# 查看 Pod 詳情
kubectl describe pod -n kommander <pod-name>

# 查看 Pod 日誌
kubectl logs -n kommander <pod-name> --previous
```

### 問題：K8s 版本不相容警告

```
Error: Kubernetes version v1.35.1 is not supported by NKP 2.16.1
Supported versions: v1.30.x - v1.33.x
```

**解決**：重建叢集，使用 1.32.4：
```bash
# 修改 inventory.ini
k8s_version=1.32.4-1.1
k8s_image_version=v1.32.4
```

---

## 參考資源

- [NKP 官方文件](https://portal.nutanix.com/page/documents/list?type=software&filterKey=software&filterVal=Nutanix%20Kubernetes%20Platform)
- [Nutanix Dev - NKP Pre-Provisioned 安裝指南](https://www.nutanix.dev/2025/11/05/deploying-nkp-in-air-gapped-environments-a-guide-to-pre-provisioned-cluster-installation-2/)
- [Polar Clouds - NKP Deployment Part 1](https://polarclouds.co.uk/nutanix-kubernetes-platform-deployment-pt1/)
- [NKP Prerequisites](https://wskn.ai/blog/nkp-prerequisites)
- [Nutanix Dev Portal](https://www.nutanix.dev)
