# CKA (Certified Kubernetes Administrator) 練習題目

這份文件包含了 16 個 CKA 考試練習題目，涵蓋了 Kubernetes 管理的各個重要方面。

## 目錄

1. [題目1 - HPA (Horizontal Pod Autoscaler)](#題目1-hpa-horizontal-pod-autoscaler)
2. [題目2 - Ingress](#題目2-ingress)
3. [題目3 - Sidecar](#題目3-sidecar)
4. [題目4 - StorageClass](#題目4-storageclass)
5. [題目5 - Service](#題目5-service)
6. [題目6 - Pod 優先級 (PriorityClass)](#題目6-pod-優先級-priorityclass)
7. [題目7 - ArgoCD](#題目7-argocd)
8. [題目8 - PVC (Persistent Volume Claim)](#題目8-pvc-persistent-volume-claim)
9. [題目9 - Gateway](#題目9-gateway)
10. [題目10 - 網路策略 (Network Policy)](#題目10-網路策略-network-policy)
11. [題目11 - 自定義資源 (CRD)](#題目11-自定義資源-crd)
12. [題目12 - ConfigMap](#題目12-configmap)
13. [題目13 - Calico](#題目13-calico)
14. [題目14 - 資源管理 (CPU 和 Memory)](#題目14-資源管理-cpu-和-memory)
15. [題目15 - ETCD 修復](#題目15-etcd-修復)
16. [題目16 - cri-dockerd](#題目16-cri-dockerd)

---

## 題目1 HPA (Horizontal Pod Autoscaler)

### 設置配置環境
```bash
kubectl config use-context k8s
```

### 任務

在 `autoscale` namespace 中創建一個名為 `apache-server` 的新 HorizontalPodAutoscaler (HPA)。
此 HPA 必須定位到 `autoscale` namespace 中名為 `apache-server` 的現有 Deployment。

- 將 HPA 設置為每個 Pod 的 CPU 使用率目標為 50%
- 將其配置為至少有 1 個 Pod，且不超過 4 個 Pod
- 此外，將縮小穩定窗口設置為 30 秒

**官網答案參考：** https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/

### 練習環境

```yaml
# apache-server-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apache-server
  namespace: autoscale
spec:
  selector:
    matchLabels:
      run: apache-server
  template:
    metadata:
      labels:
        run: apache-server
    spec:
      containers:
      - name: apache-server
        image: registry.cn-shenzhen.aliyuncs.com/cookcodeblog/hpa-example
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
        resources:
          limits:
            cpu: 500m
          requests:
            cpu: 200m
---
apiVersion: v1
kind: Service
metadata:
  name: apache-server
  namespace: autoscale
  labels:
    run: apache-server
spec:
  ports:
  - port: 80
  selector:
    run: apache-server
```

### 在線安裝 metrics-server

在線安裝 metrics-server（從 GitHub 下載 metrics-server-components.yaml）會有問題，需要在 yaml 文件中加上 `- --kubelet-insecure-tls`

```bash
wget https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml -O metrics-server-components.yaml
```

### 手動部署 metrics-server

執行部署命令：

```bash
kubectl apply -f metrics-server-components.yaml
```

部署完後，會出現短暫的 `error: Metrics API not available`，需要等待 30 秒，metrics-server 才會收集到 CPU 和 memory 資訊。

查看 metrics-server 的 pod 狀態：

```bash
kubectl -n kube-system get pods -l k8s-app=metrics-server
```

### 答案（考試時需要做的）

#### 第一步：創建 HPA 規則

```bash
kubectl autoscale deployment apache-server -n autoscale --cpu-percent=50 --min=1 --max=4
```

命令記不住可以查幫助：

```bash
kubectl autoscale --help
```

HPA（Horizontal Pod Autoscaler）創建成功了，如果 TARGETS 顯示 `(unknown)>/50%`，說明它還沒拿到當前 CPU 利用率數據，或者 metrics-server 沒有安裝成功。

metrics-server 安裝之後，就能看到 TARGETS 顯示 `0%/50%` 了。

#### 增加 CPU 負載，查看負載節點數目

```yaml
# load.yml
apiVersion: v1
kind: Pod
metadata:
  name: load-generator
spec:
  containers:
  - name: load-tester
    image: registry.cn-hangzhou.aliyuncs.com/acs/busybox:latest
    command:
      - /bin/sh
      - -c
      - |
          echo "Starting load generation..."
          while true; do
            wget -q -O- http://10.100.68.202:80
            sleep 0.01
          done
```

```bash
kubectl apply -f load.yml
```

HPA 規則已經生效，最少是 1 個，最多是 4 個。刪掉 load-generator，檢測 4 個如何變 1 個。

#### 第二步：將縮小穩定窗口設置為 30 秒

```bash
kubectl edit hpa -n autoscale apache-server
```

行為策略：

```yaml
behavior:
  scaleDown:
    stabilizationWindowSeconds: 30
```

參數記不住，就用 explain 查詢：

```bash
kubectl explain hpa.spec.behavior.scaleDown
```

#### 第三步：驗證

驗證行為策略是否添加成功：

```bash
kubectl describe hpa -n autoscale apache-server
```

---

## 題目2 Ingress

### 設置配置環境
```bash
kubectl config use-context k8s
```

### 任務

如下創建一個新的 nginx ingress 資源：

- 名稱：`pong`
- namespace：`ing-internal`
- 使用服務端口 8080 在路徑 `/hello` 上公開服務 `hello`
- 可以使用以下命令檢查服務 `hello` 的可用性，該命令返回 hello：
  ```bash
  curl -kL http://example.org/echo/
  ```

### 先檢查是否有 IngressClass 的資源

首先，要看看是否有 IngressClass 的資源，沒有的話需要自己創建。

在官網裡搜索 ingress，之後在頁面搜索 Default IngressClass 找到相應的 yaml 文件複製貼上即可。

```yaml
# default-ingressclass.yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  labels:
    app.kubernetes.io/component: controller
  name: nginx-example
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: k8s.io/ingress-nginx
```

使用 default 裡的例子，這裡 IngressClass 使用什麼名字（`name: nginx-example`），後面就要用什麼名字，需要保持一致。

### 部署 hello 服務和 Deployment（準備練習環境，考試無需此操作）

```yaml
# hello-deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
  namespace: ing-internal
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello
  template:
    metadata:
      labels:
        app: hello
    spec:
      containers:
        - name: hello
          image: docker.m.daocloud.io/library/python:3.9-alpine
          command: ["sh", "-c", "echo 'hello' > /tmp/index.html && python3 -m http.server 8000 --directory /tmp"]
          ports:
            - containerPort: 8000
---
apiVersion: v1
kind: Service
metadata:
  name: hello
  namespace: ing-internal
spec:
  selector:
    app: hello
  ports:
    - port: 8080
      targetPort: 8000
```

手動拉取鏡像：

```bash
ctr -n k8s.io images pull docker.m.daocloud.io/library/python:3.9-alpine
```

應用資源：

```bash
kubectl apply -f hello-deploy.yaml
```

驗證：

```bash
kubectl get pod -n ing-internal
kubectl get svc -n ing-internal
```

### 答案

#### 第一步：創建命名空間

```bash
kubectl create namespace ing-internal
```

#### 第二步：創建新的 nginx ingress 資源（考試時的重點操作）

創建文件 `pong-ingress.yaml`：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pong
  namespace: ing-internal
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: example.org
      http:
        paths:
          - path: /echo
            pathType: Prefix
            backend:
              service:
                name: hello
                port:
                  number: 8080
```

應用：

```bash
kubectl apply -f pong-ingress.yaml
```

查看確認：

```bash
kubectl describe ingress pong -n ing-internal
```

#### 練習環境這裡需要設置本地 hosts 映射

找到 Ingress Controller 所在節點 IP：

```bash
kubectl get pods -n ingress-nginx -o wide
kubectl get nodes -o wide
```

本機 master 節點上添加本地映射 `/etc/hosts`：

```bash
echo "192.168.31.102 example.org" >> /etc/hosts
```

#### 第三步：最終測試

CLUSTER-IP 訪問：

```bash
curl -kL http://example.org/echo/
```

NodePort 訪問：

```bash
curl -kL http://example.org:32381/echo/
```

---

## 題目3 Sidecar

### 設置配置環境
```bash
kubectl config use-context k8s
```

### 情境

您需要將一個傳統應用程式集成到 Kubernetes 的日誌架構（例如 `kubectl logs`）中。
實現這個要求的通常方法是添加一個流式傳輸並置容器。

### 任務

更新現有的 `legacy-app` pod：
- 將使用 `busybox:stable` 鏡像，且名為 `sidecar` 的並置容器，添加到現有的 Pod
- 新的並置容器必須運行以下命令：`/bin/sh -c "tail -n+1 -f /var/log/legacy-app.log"`
- 使用掛載在 `/var/log` 的 Volume，使日誌文件 `legacy-app.log` 可供並置容器使用
- 除了添加所需的卷掛載之外，請勿修改現有容器的規範

### 要點總結

你要做的是：

在現有的名為 `legacy-app` 的 Pod 中：
- 添加一個名為 `sidecar` 的容器，使用鏡像 `busybox:stable`
- 該 sidecar 容器運行的命令是：`/bin/sh -c "tail -n+1 -f /var/log/legacy-app.log"`
- 它需要通過掛載在 `/var/log` 的 Volume，讀取主容器生成的日誌
- 不能修改已有容器，只能添加 sidecar 容器和卷定義、掛載點

### 準備練習環境

```yaml
# legacy-app.yaml
apiVersion: v1
kind: Pod
metadata:
  name: legacy-app
spec:
  containers:
    - name: legacy
      image: registry.aliyuncs.com/google_containers/busybox
      command: ["/bin/sh", "-c"]
      args: ["while true; do echo 'log line' >> /var/log/legacy-app.log; sleep 5; done"]
      volumeMounts:
        - name: log-volume
          mountPath: /var/log
  volumes:
    - name: log-volume
      emptyDir: {}
```

### 答案

#### 1. 獲取並編輯該 Pod（假設是以 YAML 文件管理）

```bash
kubectl get pod legacy-app -o yaml > legacy-app.yaml
```

#### 2. 編輯 legacy-app.yaml，進行以下修改

A. 添加一個共享卷，例如 log-volume：

```yaml
volumes:
  - name: log-volume
    emptyDir: {}
```

B. 給原來的容器加掛載（如果已有就跳過）：

```yaml
containers:
  - name: legacy-container  # 你不能修改此容器的其它配置，只能添加 volumeMount
    ...
    volumeMounts:
      - name: log-volume
        mountPath: /var/log
```

⚠️ 如果原來的容器已經掛載了 `/var/log`，就不要重複添加。

C. 添加 sidecar 容器配置：

```yaml
  - name: sidecar
    image: busybox:stable
    command: ["/bin/sh", "-c"]
    args: ["tail -n+1 -f /var/log/legacy-app.log"]
    volumeMounts:
      - name: log-volume
        mountPath: /var/log
```

#### 3. 應用修改

```bash
kubectl delete pod legacy-app
kubectl apply -f legacy-app.yaml
```

⚠️ 不能直接修改運行中的 Pod，必須刪除並重建（因為 Pod 是不可變的）。

### 示例完整片段（重點部分）

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: legacy-app
spec:
  containers:
    - name: legacy-container
      image: legacy-image
      volumeMounts:
        - name: log-volume
          mountPath: /var/log
    - name: sidecar
      image: busybox:stable
      command: ["/bin/sh", "-c"]
      args: ["tail -n+1 -f /var/log/legacy-app.log"]
      volumeMounts:
        - name: log-volume
          mountPath: /var/log
  volumes:
    - name: log-volume
      emptyDir: {}
```

#### 4. 驗證

```bash
kubectl logs legacy-app -c sidecar
```

**官網參考：** https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/

---

## 題目4 StorageClass

### 設置配置環境
```bash
kubectl config use-context k8s
```

### 任務

首先，為名為 `hostpath.csi.k8s.io` 的現有佈建器，創建一個名為 `local-path` 的新 StorageClass：
- 將卷綁定模式設置為 `WaitForFirstConsumer`
- 注意，沒有設置卷綁定模式，或者將其設置為 `WaitForFirstConsumer` 之外的其他任何模式，都將導致分數降低

接下來，將 `local-path` StorageClass 配置為預設的 StorageClass：
- 請勿修改任何現有的 Deployment 和 PersistentVolumeClaim，否則將導致分數降低

### 任務要求整理

創建一個新的 StorageClass：
- 名稱：`local-path`
- 需要使用已有的 provisioner：`hostpath.csi.k8s.io`
- 設置 `volumeBindingMode: WaitForFirstConsumer`
- 設置該 StorageClass 為預設的方式：通過設置 annotation `storageclass.kubernetes.io/is-default-class: "true"`

注意：
- 不要改動任何現有的 Deployment 或 PVC
- 如果未設置 `WaitForFirstConsumer` 會被扣分
- 設置其他綁定模式也會扣分

**官網參考：**
文檔地址 依次點擊 Concepts → Storage → Storage Classes → StorageClass objects
https://kubernetes.io/docs/concepts/storage/storage-classes/

### 答案

annotations 為 "true"、volumeBindingMode 為 WaitForFirstConsumer

```yaml
# local-path-sc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: hostpath.csi.k8s.io 
reclaimPolicy: Retain # default value is Delete
volumeBindingMode: WaitForFirstConsumer
```

應用以上資源：

```bash
kubectl apply -f local-path-sc.yaml
```

檢查 `kubectl get sc`，能看到剛創建的 sc 後面有 default 即可：

```bash
kubectl get storageclass
```

---

## 題目5 Service

### 設置配置環境
```bash
kubectl config use-context k8s
```

### 任務

- 重新配置 `spline-reticulator` namespace 中現有的 `front-end` Deployment，以公開現有容器 nginx 的端口 80/tcp
- 創建一個名為 `front-end-svc` 的新 Service，以公開容器端口 80/tcp
- 配置新的 Service，以通過 NodePort 公開各個 Pod

### 練習環境準備（考試無需此操作）

```yaml
# front-end.yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: front-end
  namespace: spline-reticulator
  labels:
    app: front-end
spec:
  replicas: 1
  selector:
    matchLabels:
      app: front-end
  template:
    metadata:
      labels:
        app: front-end
    spec:
      containers:
      - name: nginx
        image: docker.m.daocloud.io/library/nginx:latest
        imagePullPolicy: IfNotPresent
```

### 答案

#### 第一步：編輯現有的 Deployment，公開 80 端口

在線編輯：

```bash
kubectl edit deploy front-end -n spline-reticulator
```

如果考試時，忘記了 yaml 格式，就查官方幫助文檔，搜索關鍵字 "Deployment"

```yaml
   ports:
   - containerPort: 80
     name: http
     protocol: TCP
```

注意這裡按空格鍵而不是 tab 進行縮進，edited 之後，保存退出後會有提示（由內容改變就是 edited，沒有就是 no changes）

#### 第二步：暴露資源：kubectl expose

```bash
kubectl expose deploy front-end \
  --name=front-end-svc \
  --port=80 \
  --target-port=80 \
  --type=NodePort \
  -n spline-reticulator
```

或者：

```bash
kubectl expose deploy front-end --name=front-end-svc -n spline-reticulator --port 80 --type NodePort
```

可以看出暴露出的端口是 80:31843/TCP，可以通過節點 IP + 端口號，訪問 front-end-svc 這個 Service。

在 Kubernetes 中，NodePort 類型的 Service 並不綁定在某一個節點上運行，而是將端口暴露在集群中每個節點的 IP 上的指定端口上（NodePort）。所以這個 Service 可以在任意一個節點的 IP + NodePort 被訪問。

---

## 題目6 Pod 優先級 (PriorityClass)

### 設置配置環境
```bash
kubectl config use-context k8s
```

### 任務

請執行以下任務：

- 為用戶工作負載創建一個名為 `high-priority` 的新 PriorityClass，其值比用戶定義的現有最高優先級類值小一
- 修改在 `priority` namespace 中運行的現有 `busybox-logger` Deployment，以使用 `high-priority` 優先級類
- 確保 `busybox-logger` Deployment 在設置了新優先級類後成功部署
- 請勿修改在 `priority` namespace 中運行的其他 Deployment，否則可能導致分數降低

**官網參考**
依次點擊 Concepts → Scheduling, Preemption and Eviction → Pod Priority and Preemption → Example PriorityClass
https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/

### 答案

#### 第一步：查看當前已有的 PriorityClass，找出用戶自定義的最高值

查看優先級：

```bash
kubectl get pc
```

其中 `system-cluster-critical` 和 `system-node-critical` 是集群預設帶的，而有一個 `max-user-priority` 是用戶自定義的。
其值為 1000000000（十位數），所以小一就是九個 9（999999999）

#### 第二步：創建一個新的 PriorityClass，值比最大用戶定義的值小 1

創建 pc，（忘記了創建命令，就使用 "--help"）：

```bash
kubectl create pc high-priority --value=999999999
```

#### 創建練習環境（考試不用做）

```yaml
# busybox-logger-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: busybox-logger
  namespace: priority
  labels:
    app: busybox-logger
spec:
  replicas: 1 
  selector:
    matchLabels:
      app: busybox-logger
  template:
    metadata:
      labels:
        app: busybox-logger
    spec:
      containers:
      - name: busybox
        image: docker.m.daocloud.io/library/busybox 
        imagePullPolicy: IfNotPresent
        args:
        - /bin/sh
        - -c
        - while true; do echo $(date -u) >> /var/log/date.log; sleep 5; done
        volumeMounts:
        - name: varlog
          mountPath: /var/log
      volumes:
      - name: varlog
        emptyDir: {} 
```

#### 第三步：編輯 busybox-logger Deployment 添加 priorityClassName

編輯 deploy：

```bash
kubectl edit deployment busybox-logger -n priority
```

正確的做法：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: busybox-logger
  namespace: priority # 確保這是正確的命名空間
  labels:
    app: busybox-logger
spec:
  replicas: 1 
  selector:
    matchLabels:
      app: busybox-logger
  template:
    metadata:
      labels:
        app: busybox-logger
    spec:
      priorityClassName: high-priority # 在這裡添加優先級類名稱
      containers:
      - name: busybox
        image: busybox 
        args:
        - /bin/sh
        - -c
        - while true; do echo $(date -u) >> /var/log/date.log; sleep 5; done
        volumeMounts:
        - name: varlog
          mountPath: /var/log
      volumes:
      - name: varlog
        emptyDir: {}
```

在 pod 的 spec 下添加（不是 deployment 的 spec）：

```yaml
priorityClassName: high-priority 
```

（記得這個要比 spec 下縮進 2 個空格）

如果忘記 priorityClassName 怎麼寫，就查官網，在官網首頁文檔處搜索 "priorityClass" 關鍵詞。

#### 第四步：驗證 Pod 是否使用了正確的 PriorityClass

驗證：

```bash
kubectl get deployment busybox-logger -n priority
kubectl get pod -n priority | grep busybox-logger 
```

查看 priority 這個 pod 下的優先級是否修改成功了。可以看到 Priority 999999999，說明優先級設置成功了。

---

## 題目7 ArgoCD

### 設置配置環境
```bash
kubectl config use-context k8s
```

**文檔** Argo Helm Charts（打開的連接是 https://argoproj.github.io/argo-helm/）

### 任務

通過執行以下任務在集群中安裝 Argo CD：

- 添加名為 `argo` 的官方 Argo CD Helm 儲存庫
- 注意：Argo CD CRD 已在集群中預安裝
- 為 `argocd` namespace 生成 Argo CD Helm 圖表版本 5.5.22 的模板，並將其保存到 `~/argo-helm.yaml`，將圖表配置為不安裝 crds
- 使用 Helm 安裝 Argo CD，並設置發布名稱為 `argocd`，使用與模板中相同的配置和版本（5.5.22），將其安裝在 `argocd` namespace 中，並配置為不安裝 crds
- 注意：您不需要配置對 Argo CD 服務器 UI 的訪問權限

### 手動安裝 Helm

下載安裝包：

```bash
curl -fsSL https://get.helm.sh/helm-v3.15.4-linux-amd64.tar.gz -o helm.tar.gz
```

解壓並安裝：

```bash
tar -zxvf helm.tar.gz
mv linux-amd64/helm /usr/local/bin/helm
chmod +x /usr/local/bin/helm
```

驗證：

```bash
helm version
```

### 自動下載並安裝最新版 Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

導出模板的語法（記不住查幫助：`helm template --help`）
helm template 的語法是：
```
helm template [NAME] [CHART] [flags]
```

題目要求安裝應用的名字為 argocd，這裡模板的名字保持和他一樣。

### 答案

#### 第一步：添加 Helm 儲存庫

```bash
helm repo add argo https://argoproj.github.io/argo-helm/
```

```bash
helm repo update
helm repo list
kubectl create ns argocd
```

添加完之後可以通過 argo 這個 name 名來 search 相關內容。

驗證 chart 是否存在版本 5.5.22：

```bash
helm search repo argo/argo-cd --versions | grep 5.5.22
```

#### 第二步：生成 Argo CD Helm 圖表版本 5.5.22 的模板（不安裝 CRDs）

生成模板文件 argo-helm.yaml：

```bash
helm template argocd argo/argo-cd \
--version 5.5.22 \
-n argocd  \
--set crds.install=false > ~/argo-helm.yaml 
```

也可以使用以下命令：

```bash
helm template argocd argo/argo-cd \
  --version 5.5.22 \
  -n argocd \
  --skip-crds > ~/argo-helm.yaml
```

#### 第三步：使用 Helm 安裝 Argo CD（不安裝 CRDs）

```bash
helm install argocd argo/argo-cd \
--version 5.5.22 \
-n argocd \
--set crds.install=false 
```

也可以使用以下命令：

```bash
kubectl create namespace argocd  # 如果 namespace 不存在則先創建

helm install argocd argo/argo-cd \
  --version 5.5.22 \
  -n argocd \
  --skip-crds
```

檢查 Helm release 是否部署成功，之後執行：

```bash
kubectl get pods -n argocd
```

看這裡的 pod，讓他自己運行即可，不用等，繼續做後面的題目。

### 步驟命令總結

```bash
# 添加 Helm 儲存庫
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# 創建命名空間
kubectl create namespace argocd

# 生成模板 YAML，跳過 CRD
helm template argocd argo/argo-cd \
  --version 5.5.22 \
  -n argocd \
  --skip-crds \
  > ~/argo-helm.yaml

# 安裝 Helm Chart，跳過 CRD
helm install argocd argo/argo-cd \
  --version 5.5.22 \
  -n argocd \
  --skip-crds
```

解釋：
- `argocd`：release 名稱
- `argo/argo-cd`：chart 名稱
- `--skip-crds`：跳過 crd 渲染
- `--version 5.5.22`：指定版本
- `--namespace argocd`：指定命名空間
- `~/argo-helm.yaml`：輸出為模板 YAML 文件

---

## 題目8 PVC (Persistent Volume Claim)

### 設置配置環境
```bash
kubectl config use-context k8s
```

### 任務

`mariadb` namespace 中的 MariaDB Deployment 被誤刪除。請恢復該 Deployment 並確保數據持久性。

請按照以下步驟：
1. 如下規格在 `mariadb` namespace 中創建名為 `mariadb` 的 PersistentVolumeClaim (PVC)：
   - 訪問模式為 `ReadWriteOnce`
   - 儲存為 `250Mi`
   - 集群中現有一個 PersistentVolume
   - 您必須使用現有的 PersistentVolume (PV)

2. 編輯位於 `~/mariadb-deployment.yaml` 的 MariaDB Deployment 文件，以使用上一步中創建的 PVC

3. 將更新的 Deployment 文件應用到集群

4. 確保 `mariadb` Deployment 正在運行且穩定

### 文件內容如下

```yaml
# mariadb-deployment.yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mariadb
  namespace: mariadb
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mariadb
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
      - name: mariadb
        image: docker.m.daocloud.io/library/mariadb:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 3306
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: "123456"
        volumeMounts:
        - name: mysql-persistent-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-persistent-storage
        persistentVolumeClaim:
          claimName: mariadb 
```

### 創建 PV（考試不用做，會自動創建）

```yaml
# pv.yml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mariadb-pv
spec:
  capacity:
    storage: 250Mi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: slow
  claimRef:
    kind: PersistentVolumeClaim
    namespace: mariadb
    name: mariadb
  hostPath:
    path: /mnt/data/mariadb
```

### 答案

#### 第一步：先查看 PV

執行 `kubectl get pv`，查看 STORAGECLASS 那列的值，這裡為 SLOW，考試時看清具體的值（此值 PVC 需和 PV 保持一致）。

```bash
kubectl get pv
```

#### 第二步：創建 PVC

創建文件 8-pvc.yaml（資源不會寫可以查官網模板）：

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb
  namespace: mariadb
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: 250Mi
  storageClassName: slow  
```

**官網模板：** https://kubernetes.io/docs/concepts/storage/persistent-volumes/

創建 PVC 資源：

```bash
kubectl apply -f 8-pvc.yaml -n mariadb
```

驗證是否關聯在一起了：

```bash
kubectl get pvc
```

此時 PV 和 PVC 已經通過 slow 這個 StorageClass 綁定（Bound）在一起了。

---

## 題目9 Gateway

### 設置配置環境
```bash
kubectl config use-context k8s
```

### 任務

將現有 Web 應用程式從 Ingress 遷移到 Gateway API。您必須維護 HTTPS 訪問權限。

注意：集群中安裝了一個名為 `nginx` 的 GatewayClass。

1. 首先，創建一個名為 `web-gateway` 的 Gateway，主機名為 `gateway.web.k8s.local`，並保持現有名為 `web` 的 Ingress 資源的現有 TLS 和監聽器配置

2. 接下來，創建一個名為 `web-route` 的 HTTPRoute，主機名為 `gateway.web.k8s.local`，並保持現有名為 `web` 的 Ingress 資源的現有路由規則

3. 您可以使用以下命令測試 Gateway API 配置：
   ```bash
   curl -Lk https://gateway.web.k8s.local:31144
   ```

4. 最後，刪除名為 `web` 的現有 Ingress 資源

### 答案

#### 第一步：先查名為 web 的 ingress 的屬性，找到 secretName

查看已有 Ingress 的配置：

```bash
kubectl get ingress web -o yaml    # ing是ingress的縮寫
```

重點查看：
- host: `gateway.web.k8s.local`
- tls.secretName: 比如是 `web-cert`
- backend service: 比如是 `web:80`

ingress 的名字為 web，先查詢這個名字為 web 的 ingress 的屬性，`kubectl get ing web -o yaml`，在最後幾行能看到用到的 secret 名字。

假設 web 的 Service 此時服務通過 ingress 已經發布出去，能夠正常訪問，還要找到所使用服務的名字創建網關。

查看是否存在 Secret（TLS 證書）：

```bash
kubectl get secret web-cert -n default
```

#### 第二步：創建 Gateway.yaml

**文檔地址：**
Concepts → Services, Load Balancing, and Networking → Gateway API → Gateway 和
Concepts → Services, Load Balancing, and Networking → Gateway API → HTTPRoute
https://kubernetes.io/docs/concepts/services-networking/gateway/

這裡的 yaml 地址需要參考文檔然後修改，下面 tls 及下面的 3 行加黑部分記住它：

```yaml
    tls:
      certificateRefs:
        - name: web-cert
```

或者通過 `kubectl explain gtw.spec | grep list`，知道 listeners 的拼寫，然後繼續下面的命令：

```bash
kubectl explain gtw.spec.listeners.tls 
kubectl explain gtw.spec.listeners.tls.certificateRefs
```

逐步查看出來，創建：

```yaml
# 9-gtw.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gateway
spec:
  gatewayClassName: nginx
  listeners:
    - name: foo-https
      protocol: HTTPS
      port: 443
      hostname: gateway.web.k8s.local
      tls:
        certificateRefs:
          - name: web-cert
```

```bash
kubectl apply -f 9-gtw.yaml 
kubectl get gtw
```

#### 第三步：創建 HTTPRoute.yaml

建立 HTTPRoute
這個就從官網複製，並修改：

```yaml
# 9-httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
spec:
  parentRefs:
    - name: web-gateway
  hostnames:
    - "gateway.web.k8s.local" 
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: web 
          port: 80
```

練習的時候需要添加，IP 替換為 node 的地址：

```bash
# /etc/hosts
192.168.10.22  gateway.web.k8s.local
```

```bash
kubectl apply -f 9-httproute.yaml 
kubectl get httproutes 
```

#### 第四步：驗證是否生效

```bash
curl -k https://gateway.web.k8s.local:31144
```

#### 最後：刪除舊的 Ingress 資源

刪除 ingress：

```bash
kubectl delete ingress web -n default
```

---

## 題目10 網路策略 (Network Policy)

### 設置配置環境
```bash
kubectl config use-context k8s
```

### 任務

從提供的 YAML 樣本中查看並應用適當的 NetworkPolicy。

確保選擇的 NetworkPolicy 不過於寬鬆，同時允許運行在 `frontend` 和 `backend` namespaces 中的 `frontend` 和 `backend` Deployment 之間的通信。

1. 首先，分析 `frontend` 和 `backend` Deployment，以確定需要應用的 NetworkPolicy 的具體要求

2. 接下來，檢查位於 `~/netpol` 資料夾中的 NetworkPolicy YAML 示例

3. 注意：請勿刪除或修改提供的示例。僅應用其中一個。否則可能會導致分數降低

4. 最後，應用啟用 `frontend` 和 `backend` Deployment 之間的通信的 NetworkPolicy，但不要過於寬容

5. 注意：請勿刪除或修改現有的預設拒絕所有入站流量或出口流量 NetworkPolicy。否則可能導致零分

### 答案

查看 `~/netpol` 裡幾個策略的內容：
- 第一個文件是允許命名空間 `frontend` 裡所有的 pod 都能訪問
- 第二個策略：允許 `frontend` namespace 下有 `app=frontend` 標籤的 Pod，訪問 `backend` namespace 下有 `app=backend` 標籤的 Pod
- 第二個比第一個策略更合適，第一個開放的範圍太多了
- 第三個策略：看到 `backend` namespace 下有 `app=database` 標籤的 Pod，就不用看了。這個顯然是錯誤的，`backend` namespace 下的 Pod，標籤是 `app=backend`，而不是 `app=database`

所以，最終選擇 `netpol2.yaml` 創建：

```bash
kubectl apply -f ~/netpol/netpol2.yaml
```

### 詳細答案

#### ① 查看 frontend 和 backend 的部署資訊

```bash
kubectl get deploy -n frontend
kubectl get deploy -n backend

kubectl get pods -n frontend -o wide
kubectl get pods -n backend -o wide
```

你要知道 `frontend` 和 `backend` 的 Pod 是否通過 label 選擇器識別，比如：

```yaml
labels:
  app: frontend
```

#### ② 查看 frontend 是否需要訪問 backend

你需要確認是：
- frontend → backend：需要放通
- backend → frontend：不需要放通（通常情況）

#### ③ 查看 ~/netpol 目錄下的 YAML 示例

```bash
ls ~/netpol
```

依次查看文件內容：

```bash
cat ~/netpol/policy-1.yaml
cat ~/netpol/policy-2.yaml
...
```

找到那個允許 `frontend` namespace 的 Pod 訪問 `backend` namespace 的 Pod，且其他不放通的策略。

🎯 理想策略具備以下特徵：

```yaml
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: backend
spec:
  podSelector: {}  # 作用於 backend 中所有 pod
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: frontend
      ports:
        - port: 80
```

⚠️ 注意：
- 不能用 `from: [{}]` 這樣寬鬆的配置
- 不應該放通所有命名空間
- 不應該添加出口規則（除非明確要求）
- 不能刪除已有的 default deny 策略

#### ④ 應用最合適的 NetworkPolicy

確認選擇後：

```bash
kubectl apply -f ~/netpol/policy-X.yaml
```

#### ⑤ 驗證（可選）

你可以測試 frontend pod 是否可以訪問 backend pod：

```bash
kubectl exec -n frontend <frontend-pod> -- curl <backend-service>:<port>
```

---

## 題目11 自定義資源 (CRD)

### 設置配置環境
```bash
kubectl config use-context k8s
```

### 任務

驗證已部署到集群的 cert-manager 應用程式。

1. 使用 kubectl，將 cert-manager 所有定制資源定義（CRD）的列表，保存到 `~/resources.yaml`
   - 注意：您必須使用 kubectl 的預設輸出格式。請勿設置輸出格式。否則將導致分數降低

2. 使用 kubectl，提取定制資源 Certificate 的 subject 規範字段的文檔，並將其保存到 `~/subject.yaml`
   - 注意：您可以使用 kubectl 支持的任何輸出格式。如果不確定，請使用預設輸出格式

### 準備練習環境，安裝 cert-manager（考試不用做）

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.3 \
  --set installCRDs=true
```

### 答案

#### 1. 先查看 cert-manager 裡的 pod 正常運行

```bash
kubectl get pods -n cert-manager
```

#### 2. 然後找到 cert-manager 相關的 crd

```bash
kubectl get crd | grep cert-manager
```

或

```bash
kubectl get crd -l app.kubernetes.io/name=cert-manager
```

#### 3. 保存內容

保存到指定的文件：

```bash
kubectl get crd | grep cert-manager > ~/resources.yaml 
```

或

```bash
kubectl get crd -l app.kubernetes.io/name=cert-manager > ~/resources.yaml
```

#### 4. 保存內容：kubectl explain certificate.spec.subject > ~/subject.yaml

找到題目要求的字段，保存到指定的文件：

```bash
kubectl explain certificate.spec.subject > ~/subject.yaml
```

```bash
kubectl explain certificate.spec.subject
```

### 如何一步步查字段路徑？

你可以用 kubectl explain 逐級展開，比如：

```bash
kubectl explain certificate          # 查看頂層字段，確認有spec
kubectl explain certificate.spec     # 查看spec下的字段，有subject
kubectl explain certificate.spec.subject
```

---

## 題目12 ConfigMap

### 設置配置環境
```bash
kubectl config use-context k8s
```

### 任務

名為 `nginx-static` 的 NGINX Deployment 正在 `nginx-static` namespace 中運行。
它通過名為 `nginx-config` 的 ConfigMap 進行配置。
更新 `nginx-config` ConfigMap 以僅允許 TLSv1.3 連接。

注意：您可以根據需要重新創建、重新啟動或擴展資源。

您可以使用以下命令測試更改：
```bash
curl -k --tls-max 1.2 https://web.k8snginx.local
```

### 練習環境準備（考試不需要做）

```yaml
# nginx-tls12.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nginx-static
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: nginx-static
data:
  nginx.conf: |
    user  nginx;
    worker_processes  auto;

    error_log  /var/log/nginx/error.log notice;
    pid        /var/run/nginx.pid;

    events {
        worker_connections  1024;
    }

    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;

        access_log  /var/log/nginx/access.log;

        sendfile        on;
        keepalive_timeout  65;

        gzip  on;

        server {
            listen       80;
            server_name  localhost;

            return 301 https://$host$request_uri;
        }

        server {
            listen       443 ssl;
            server_name  web.k8snginx.local;

            ssl_certificate      /etc/nginx/ssl/tls.crt;
            ssl_certificate_key  /etc/nginx/ssl/tls.key;

            # 只允許 TLSv1.2
            ssl_protocols TLSv1.2;

            location / {
                root   /usr/share/nginx/html;
                index  index.html index.htm;
                try_files $uri $uri/ =404;
            }
        }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-static
  namespace: nginx-static
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: docker.m.daocloud.io/library/nginx:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
        - containerPort: 443
        volumeMounts:
        - name: nginx-config-volume
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: tls-certs
          mountPath: /etc/nginx/ssl
      volumes:
      - name: nginx-config-volume
        configMap:
          name: nginx-config
      - name: tls-certs
        secret:
          secretName: nginx-tls
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: nginx-static
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 443
      targetPort: 443
      nodePort: 30443
```

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=web.k8snginx.local"
```

```bash
kubectl create secret tls nginx-tls \
  --cert=tls.crt \
  --key=tls.key \
  -n nginx-static
```

```bash
echo "10.100.68.202 web.k8snginx.local" | sudo tee -a /etc/hosts
```

啟動成功後，可以通過 NodePort 的端口訪問這個 nginx 服務。

```bash
curl -k --tls-max 1.2 https://web.k8snginx.local
```

### 答案

#### 第一步：先測試

```bash
curl -k --tls-max 1.2 https://web.k8snginx.local 
```

#### 第二步：先備份後修改

建議備份一份：

```bash
kubectl get configmaps nginx-config -n nginx-static
kubectl get configmap nginx-config -n nginx-static -o yaml > nginx-config.yaml 
```

然後再修改：

```bash
kubectl edit configmap -n nginx-static nginx-config
```

#### 第三步：刪除 TLSv1.2

刪除裡面的 `TLSv1.2`，改成 `TLSv1.3`，按 esc，保存退出重啟 deployment。

#### 第四步：滾動更新測試

```bash
kubectl rollout restart deployment nginx-static -n nginx-static
```

之後測試：

```bash
curl -k --tls-max 1.3 https://web.k8snginx.local
curl -k --tls-max 1.2 https://web.k8snginx.local
```

---

## 題目13 Calico

### 設置配置環境
```bash
kubectl config use-context k8s
```

**文檔地址**
- Flannel Manifest：https://github.com/flannel-io/flannel/releases/download/v0.26.1/kube-flannel.yml
- Calico Manifest：https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

集群的 CNI 未通過安全審核，已被移除。您必須安裝一個可以實施網路策略的新 CNI。

### 任務

安裝並設置滿足以下要求的容器網路接口（CNI）：
選擇並安裝以下 CNI 選項之一：
- Flannel 版本 0.26.1
- Calico 版本 3.28.2

選擇的 CNI 必須：
- 讓 Pod 相互通信
- 支持 Network Policy 實施
- 從清單文件安裝（請勿使用 Helm）

### 答案

#### 第一步：下載並編輯官方提供的 tigera-operator.yaml

因為題目要求支持 Network Policy 實施，而 Flannel 其實不支持 Network Policy，所以只能選擇支持的 Calico 部署。

下載 tigera-operator：

```bash
wget https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml 
```

部署 tigera-operator 必須使用 kubectl create 而非 apply。
直接使用 apply 可能導致 CRD 衝突。

```bash
kubectl create -f tigera-operator.yaml
```

查看集群的 CIDR 地址，一般預設：

```bash
kubectl cluster-info dump | grep -i cidr
```

都是 `10.244.0.0/16`，但是這裡還是要去查一下。

#### 第二步：安裝 Calico CRD（CustomResource）

下載 CRD
這個網址題目沒有給你，其實就是將上一步網址中的 `tigera-operator.yaml` 改成 `custom-resources.yaml`，所以這個單詞一定要背過。

```bash
wget https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml 
```

注意後面的 yaml 文件名稱 "custom-resources" 是和前面下載的不同地方，把他記住。這個文件的內容很少，修改裡面的 CIDR，修改成前面查到的。

然後運行：

```bash
kubectl create -f custom-resources.yaml
```

#### 第三步：確認安裝成功，確保 calico-node DaemonSet 運行中

```bash
kubectl get pods -n kube-system -l k8s-app=calico-node
```

---

## 題目14 資源管理 (CPU 和 Memory)

**考察：** 設置合理的 CPU 和記憶體請求，並確保資源公平分配且 Pod 可正常運行

### 設置配置環境
```bash
kubectl config use-context k8s
```

### 情境
您管理一個 WordPress 應用程式。由於資源請求過高，某些 Pod 無法啟動。

### 任務

`relative-fawn` namespace 中的 WordPress 應用程式包含：
- 具有 3 個副本的 WordPress Deployment

按如下方式調整所有 Pod 資源請求：
- 將節點資源平均分配給這 3 個 Pod
- 為每個 Pod 分配公平的 CPU 和記憶體份額
- 添加足夠的開銷以保持節點穩定
- 請確保，對容器和初始化容器使用完全相同的請求
- 您無需更改任何資源限制

在更新資源請求時，暫時將 WordPress Deployment 縮放為 0 個副本可能會有所幫助。

更新後，請確認：
- WordPress 保持 3 個副本
- 所有 Pod 都在運行並準備就緒

### 將 WordPress Deployment 縮放為 0 個副本

題目裡明確指明，要先將 Deployment 縮放為 0。
考試時，如果不將其縮小為 0，而是直接修改 CPU 和 memory 值，會導致新 Pod 起不來，因為考試環境提前做了一些限制。

```bash
kubectl scale deployment wordpress -n relative-fawn --replicas=0 
```

### 檢查 nodes 資源請求情況

考試只有一個 node 節點，模擬環境裡，我們假設是 `vms22.rhce.cc` 這個 node 節點即可。

要先縮為 0 後，再檢查 node 資源請求情況。

```bash
kubectl get nodes 
kubectl describe node vms22.rhce.cc
```

CPU 550m 占用了 27%，可計算出大約每 1% 是 20m。

因為當前已經申請用了 27%，所以還剩下 73% 可供申請，也就是一共還剩 1460m 可以申請。（20m*73）
然後，這個 deployment 裡面有 2 個 containers 容器（含一個初始化容器），
而且最終是要 3 副本，所以一共有 6 個 containers 平分 1460m，每個 containers 約可以分 243m（1460m 被 6 個容器分，即 1460/6）。
所以每個 containers 的 CPU requests 上限不能超過 243m，所以理論上 CPU request：1m-243m 都可以設置。
這裡就設置 100m，因為太低了，可能也會導致 Pod 獲取不到資源。

同樣的方法，memory request 360Mi 占 9%，所以大於每 1% 為 40Mi。剩餘 91% 可供申請，也就是剩餘 3640Mi。
讓 6 個 containers 平分，所以每個最高是 606Mi。這裡就設置為 200Mi。

如果不會計算的話，只需要記住考試時，
這道題 requests CPU 也是設置為 100m，
requests memory 也是設置為 200Mi，就可以保證 Pod 正常 Running。
因為考試做了一些隱形限制，如果 request 過低或者過高，都會讓 Pod 無法啟動。

```bash
kubectl scale deployment wordpress -n relative-fawn --replicas=3
```

### 答案

#### 第一步：先縮容副本數為 0

```bash
kubectl scale deployment wordpress -n relative-fawn --replicas=0
```

#### 第二步：修改 Deployment 資源（包括容器和 init 容器 requests）

推薦設置：每個容器 CPU request: 100m
推薦設置：每個容器 memory request: 200Mi

```bash
kubectl edit deployment wordpress -n relative-fawn
```

找到 `spec.template.spec.containers` 和 `initContainers` 部分，在每個容器中添加以下內容：

```yaml
# 注意看是否有如下兩個設置一樣的值
containers:
- name: wordpress
  resources:
    requests:
      cpu: 100m
      memory: 200Mi

initContainers:
- name: init-wordpress
  resources:
    requests:
      cpu: 100m
      memory: 200Mi
```

上面步驟不要改動 limits 的部分，只改 requests！

（如果忘記了怎麼寫，可以在官方文檔中搜索 "resources" 關鍵字）
**官方幫助文檔：** https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

#### 第三步：恢復副本數為 3

```bash
kubectl scale deployment wordpress -n relative-fawn --replicas=3
# 檢查pod
kubectl get pods -n relative-fawn -w
```

---

## 題目15 ETCD 修復

**排查並修復單節點集群在遷移後失效的原因**

### 設置配置環境
```bash
kubectl config use-context k8s
```

### 情境
kubeadm 配置的集群已遷移到新機器。它需要更改配置才能成功運行。

### 任務

修復在機器遷移過程中損壞的單節點集群。

1. 首先，確定損壞的集群組件，並調查導致其損壞的原因
   - 注意：已停用的集群使用外部 ETCD 伺服器

2. 接下來，修復所有損壞的集群組件的配置
   - 注意：確保重新啟動所有必要的服務和組件，以使更改生效。否則可能導致分數降低

3. 最後，確保集群運行正常。確保：每個節點和所有 Pod 都處於 Ready 狀態

### 答案

### 修改兩個文件

#### 第一個文件：/etc/kubernetes/manifests/kube-apiserver.yaml

```bash
vim /etc/kubernetes/manifests/kube-apiserver.yaml
```

這個地址改成 `127.0.0.1`

#### 第二個文件：/etc/kubernetes/manifests/kube-scheduler.yaml

```bash
vim /etc/kubernetes/manifests/kube-scheduler.yaml
```

這裡的 CPU 的值由 4 改為 100m，整個文件裡就這一處 CPU。

#### 重啟服務

```bash
systemctl restart kubelet 
kubectl get nodes
```

---

## 題目16 cri-dockerd

**關於為 Kubernetes 使用 cri-dockerd 做節點準備的題型**

### 設置配置環境
```bash
kubectl config use-context k8s
```

### 情境
您的任務是為 Kubernetes 準備一個 Linux 系統。Docker 已被安裝，但您需要為 kubeadm 配置它。

### 任務

完成以下任務，為 Kubernetes 準備系統：

1. 設置 cri-dockerd：
   - 安裝 Debian 軟體包 `~/cri-dockerd_0.3.6.3-0.ubuntu-jammy_amd64.deb`
   - Debian 軟體包使用 dpkg 安裝
   - 啟用並啟動 cri-docker 服務

2. 配置以下系統參數：
   - `net.bridge.bridge-nf-call-iptables` 設置為 1
   - `net.ipv6.conf.all.forwarding` 設置為 1
   - `net.ipv4.ip_forward` 設置為 1
   - `net.netfilter.nf_conntrack_max` 設置為 131072
   
3. 確保這些系統參數在系統重啟後仍然存在，並應用於正在運行的系統

### 答案

#### 第一步：安裝軟體包

```bash
sudo dpkg -i ~/cri-dockerd_0.3.6.3-0.ubuntu-jammy_amd64.deb
```

#### 第二步：啟用服務

啟動服務：

```bash
sudo systemctl enable cri-docker 
```

#### 第三步：配置系統參數 /etc/sysctl.conf

配置題目要求的參數

修改配置文件：

```bash
sudo vim /etc/sysctl.conf 
```

在最後面添加如下參數：

```bash
net.bridge.bridge-nf-call-iptables=1 
net.ipv6.conf.all.forwarding=1 
net.ipv4.ip_forward=1 
net.netfilter.nf_conntrack_max=131072 
```

#### 第四步：生效配置

保存退出之後，按如下命令讓參數生效：

```bash
sudo sysctl -p /etc/sysctl.conf
```

---

## 總結

本文檔包含了 CKA 考試的 16 個重要練習題目，涵蓋了 Kubernetes 管理的各個重要面向：

1. **HPA** - 水平 Pod 自動擴縮
2. **Ingress** - 入口控制器配置
3. **Sidecar** - 邊車容器模式
4. **StorageClass** - 儲存類別配置
5. **Service** - 服務發布
6. **PriorityClass** - Pod 優先級管理
7. **ArgoCD** - GitOps 工具部署
8. **PVC** - 持久卷聲明
9. **Gateway** - 網關 API
10. **Network Policy** - 網路策略
11. **CRD** - 自定義資源定義
12. **ConfigMap** - 配置管理
13. **Calico** - CNI 網路插件
14. **資源管理** - CPU 和記憶體分配
15. **ETCD 修復** - 集群故障排除
16. **cri-dockerd** - 容器運行時配置

每個題目都提供了完整的問題描述、解決方案和相關的 YAML 配置文件，幫助準備 CKA 認證考試。

建議在實際環境中練習這些題目，以熟悉 Kubernetes 的各種操作和概念。

---

**版權聲明：** 本文為 CSDN 博主「flytalei」的原創文章，遵循 CC 4.0 BY-SA 版權協議，轉載請附上原文出處連結及本聲明。
**原文連結：** https://blog.csdn.net/flytalei/article/details/148094877