# Lab: Deploy NVIDIA NIM on DigitalOcean with GPU Monitoring

This lab guides you through deploying NVIDIA NIM on DigitalOcean Kubernetes (DOKS) with comprehensive GPU monitoring using Prometheus and Grafana.

## Prerequisites

- DigitalOcean account with billing enabled
- doctl CLI tool installed and configured
- kubectl installed
- Helm installed
- NVIDIA API key for NIM container access

### Install and Configure doctl

```bash
# Install doctl (macOS with Homebrew)
brew install doctl

# Or download from GitHub releases
# https://github.com/digitalocean/doctl/releases

# Authenticate with your DigitalOcean API token
doctl auth init

# You'll be prompted to enter your API token
# Get your API token from: https://cloud.digitalocean.com/account/api/tokens
# Make sure to select "Full Access" scope

# Verify authentication
doctl account get
```

## Step 0: Request GPU Access

DigitalOcean requires that you request access to GPU nodes before you can provision them.

1. Go to your DigitalOcean control panel
2. Submit a support ticket requesting access to GPU Droplets or nodes
3. In the request, explain your use case (e.g., "training AI models in a Kubernetes cluster")
4. Wait for confirmation from DigitalOcean

## Step 1: Create or Connect to DigitalOcean H100 Cluster

### Option A: Create a New H100 Cluster (Toronto Region)

If you need to create a new cluster with H100 GPU nodes:

```bash
# Set environment variables for Toronto region
export CLUSTER_NAME=nim-h100-cluster
export REGION=tor1  # Toronto region
export GPU_NODE_SIZE=gpu-20vcpu-240gb  # H100 GPU node

# Create the cluster with H100 GPU node pool
doctl kubernetes cluster create ${CLUSTER_NAME} \
  --region ${REGION} \
  --version latest \
  --node-pool "name=h100-worker-pool;size=${GPU_NODE_SIZE};count=1"

# Download cluster credentials
doctl kubernetes cluster kubeconfig save ${CLUSTER_NAME}

# Verify cluster connection and GPU node
kubectl get nodes
kubectl describe nodes | grep -A 5 "nvidia.com/gpu"

# Verify H100 GPU is available
kubectl get nodes -o json | jq '.items[].status.allocatable | select(."nvidia.com/gpu")'
```

### Option B: Connect to Existing H100 Cluster

If you already have a DigitalOcean Kubernetes cluster with an NVIDIA H100 GPU node:

```bash
# Set your cluster name (replace with your actual cluster name)
export CLUSTER_NAME=your-existing-cluster-name

# Download cluster credentials
doctl kubernetes cluster kubeconfig save ${CLUSTER_NAME}

# Verify cluster connection and GPU node
kubectl get nodes
kubectl describe nodes | grep -A 5 "nvidia.com/gpu"

# Verify H100 GPU is available
kubectl get nodes -o json | jq '.items[].status.allocatable | select(."nvidia.com/gpu")'
```

**H100 Node Specifications**:
- **GPU**: 1x NVIDIA H100 (80GB VRAM)
- **vCPU**: 20 cores
- **vRAM**: 240 GB
- **Storage**: 720 GB
- **Cost**: $3.39/hour (~$2,500/month if running 24/7)
- **Region**: Toronto (tor1)

## Step 2: Install NVIDIA GPU Operator

The NVIDIA GPU operator automatically installs GPU drivers and other components, including the DCGM Exporter for monitoring.

```bash
# Add NVIDIA Helm repository
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# Install the GPU operator
helm install --wait --generate-name \
  -n gpu-operator --create-namespace \
  nvidia/gpu-operator

# Verify GPU operator installation
kubectl get pods -n gpu-operator
```

## Step 3: Deploy NVIDIA NIM (Optimized for H100)

Deploy a larger model that can take advantage of the H100's 80GB VRAM. We'll use Llama 3.1 70B which is much more suitable for the H100's capabilities.

```bash
# Set NVIDIA API key
export NVIDIA_API_KEY="your-nvidia-api-key"

# Create namespace for NIM
kubectl create namespace nim

# Create secret for NVIDIA API key
kubectl create secret generic nim-api-key \
  --from-literal=api-key=${NVIDIA_API_KEY} \
  -n nim

# Deploy NIM with Llama 3.1 70B model (better suited for H100)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nim-sa
  namespace: nim
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: nim-role
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: nim-role-binding
subjects:
- kind: ServiceAccount
  name: nim-sa
  namespace: nim
roleRef:
  kind: ClusterRole
  name: nim-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llama-3-1-70b
  namespace: nim
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llama-3-1-70b
  template:
    metadata:
      labels:
        app: llama-3-1-70b
    spec:
      serviceAccountName: nim-sa
      nodeSelector:
        nvidia.com/gpu: "1"
      containers:
      - name: llama-3-1-70b
        image: nvcr.io/nim/llama-3.1-70b:latest
        ports:
        - containerPort: 8000
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: "200Gi"  # H100 has 240GB RAM, leave some for system
          requests:
            nvidia.com/gpu: 1
            memory: "200Gi"
        env:
        - name: NVIDIA_API_KEY
          valueFrom:
            secretKeyRef:
              name: nim-api-key
              key: api-key
        - name: CUDA_VISIBLE_DEVICES
          value: "0"
        - name: NVIDIA_VISIBLE_DEVICES
          value: "all"
---
apiVersion: v1
kind: Service
metadata:
  name: llama-3-1-70b-service
  namespace: nim
spec:
  selector:
    app: llama-3-1-70b
  ports:
  - port: 8000
    targetPort: 8000
  type: LoadBalancer
EOF

# Verify NIM deployment
kubectl get pods -n nim
kubectl get svc -n nim

# Monitor pod startup (H100 models take longer to load)
kubectl logs -f deployment/llama-3-1-70b -n nim
```

## Step 4: Install Prometheus and Grafana for Monitoring

Install the monitoring stack to observe GPU performance and NIM metrics.

```bash
# Add Prometheus community Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus stack
helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

## Step 5: Configure Prometheus to Scrape DCGM Metrics

Configure Prometheus to collect GPU metrics from the DCGM Exporter.

```bash
# Create ServiceMonitor for DCGM Exporter
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nvidia-dcgm-exporter
  namespace: monitoring
  labels:
    prometheus: prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: dcgm-exporter
  endpoints:
  - port: metrics
    interval: 15s
EOF

# Verify DCGM Exporter is running
kubectl get pods -n gpu-operator | grep dcgm-exporter

# Test metrics endpoint
kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400 &
curl localhost:9400/metrics | head -20
```

## Step 6: Access Grafana and Import GPU Dashboard

Set up Grafana to visualize GPU metrics and NIM performance.

```bash
# Get Grafana admin password
kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode

# Port-forward Grafana service
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80 &
```

1. Open your browser and navigate to `http://localhost:3000`
2. Log in with username `admin` and the password from above
3. Go to Dashboards → Import
4. Enter dashboard ID: `12239` (NVIDIA DCGM Exporter dashboard)
5. Select Prometheus as data source
6. Click Import

## Step 7: Test NIM API and Monitor Performance

Test the NIM deployment while monitoring GPU usage in Grafana.

```bash
# Get external IP of NIM service
EXTERNAL_IP=$(kubectl get svc llama-3-1-70b-service -n nim -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test NIM API with a more complex prompt to showcase H100 capabilities
curl -X POST "http://$EXTERNAL_IP:8000/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-3.1-70b",
    "messages": [
      {"role": "user", "content": "Explain the differences between transformer architectures and how they impact model performance. Provide a detailed technical analysis."}
    ],
    "max_tokens": 500,
    "temperature": 0.7
  }'
```

While the API call is running, observe in Grafana:
- **GPU utilization** (should see high usage with 70B model)
- **VRAM usage** (expect ~40-60GB usage for Llama 3.1 70B)
- **Temperature** (H100 can handle up to 83°C)
- **Power consumption** (H100 can draw up to 700W)
- **Memory bandwidth** (H100 has 3.35 TB/s bandwidth)
- **Inference latency** (should be much faster than smaller GPUs)

## Step 8: Advanced Monitoring Setup

### Monitor NIM Application Metrics

Create custom ServiceMonitor for NIM application metrics:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nim-application
  namespace: monitoring
  labels:
    prometheus: prometheus-stack
spec:
  selector:
    matchLabels:
      app: llama-3-1-70b
  endpoints:
  - port: 8000
    interval: 30s
    path: /metrics
EOF
```

### Set up Alerts for GPU Issues

```bash
# Create alert rules for GPU monitoring
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gpu-alerts
  namespace: monitoring
  labels:
    prometheus: prometheus-stack
spec:
  groups:
  - name: gpu.rules
    rules:
    - alert: HighGPUTemperature
      expr: DCGM_FI_DEV_GPU_TEMP > 85  # H100 can handle higher temps
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "H100 GPU temperature is high"
        description: "H100 GPU temperature is {{ \$value }}°C"
    - alert: HighGPUUtilization
      expr: DCGM_FI_DEV_GPU_UTIL > 95
      for: 10m
      labels:
        severity: info
      annotations:
        summary: "H100 GPU utilization is very high"
        description: "H100 GPU utilization is {{ \$value }}%"
    - alert: HighVRAMUsage
      expr: DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL > 0.9
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "H100 VRAM usage is very high"
        description: "H100 VRAM usage is {{ \$value | humanizePercentage }}"
EOF
```

## Step 9: Cost Optimization Tips

Since your H100 cluster costs $3.39/hour (~$2,500/month if running 24/7), here are some cost optimization strategies:

### Scale Down When Not in Use
```bash
# Scale down NIM deployment to 0 replicas when not needed
kubectl scale deployment llama-3-1-70b --replicas=0 -n nim

# Scale back up when needed
kubectl scale deployment llama-3-1-70b --replicas=1 -n nim
```

### Use Horizontal Pod Autoscaler (HPA)
```bash
# Install metrics-server if not already installed
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Create HPA for NIM deployment
kubectl autoscale deployment llama-3-1-70b --cpu-percent=50 --min=0 --max=1 -n nim
```

### Monitor Costs
```bash
# Check current resource usage
kubectl top nodes
kubectl top pods -n nim

# Monitor GPU utilization
kubectl exec -n gpu-operator deployment/nvidia-dcgm-exporter -- nvidia-smi
```

### Schedule Workloads
Consider using Kubernetes CronJobs for batch processing during off-peak hours to optimize costs.

## Step 10: Cleanup

**Important**: Your H100 cluster costs $3.39/hour. To avoid unexpected charges:

### Option 1: Scale Down (Recommended for temporary pause)
```bash
# Scale down all workloads
kubectl scale deployment llama-3-1-70b --replicas=0 -n nim
kubectl scale deployment prometheus-stack-grafana --replicas=0 -n monitoring
kubectl scale deployment prometheus-stack-prometheus --replicas=0 -n monitoring

# The cluster will still cost $3.39/hour but with minimal resource usage
```

### Option 2: Delete Cluster (Only if you're completely done)
```bash
# WARNING: This will delete your entire cluster and all data
doctl kubernetes cluster delete ${CLUSTER_NAME}
```

## Lab Objectives Achieved

This lab successfully demonstrates:

1. **GPU Cluster Management**: Creating and managing GPU-enabled Kubernetes clusters on DigitalOcean
2. **NVIDIA NIM Deployment**: Deploying AI models using NIM with proper resource allocation
3. **Monitoring & Observability**: Setting up comprehensive GPU monitoring with Prometheus and Grafana
4. **MLOps Best Practices**: Using Helm for reproducible deployments and Kubernetes for scaling
5. **Performance Analysis**: Monitoring GPU utilization, memory usage, and application performance

## Key Advantages of DigitalOcean H100 Approach

- ✅ **High-Performance GPU**: H100 with 80GB VRAM for large models
- ✅ **Predictable Pricing**: $3.39/hour (~$2,500/month for 24/7 usage)
- ✅ **No GPU quota restrictions**: Unlike other cloud providers
- ✅ **Immediate GPU access**: After approval process
- ✅ **Comprehensive monitoring**: Full GPU metrics and application monitoring
- ✅ **Easy scaling**: Kubernetes-native scaling and resource management
- ✅ **Cost optimization**: Scale down when not in use to save costs

## Next Steps

1. **Optimize for H100**: Experiment with larger models (Llama 3.1 405B, Mixtral 8x22B)
2. **Implement auto-scaling**: Use HPA and VPA for dynamic resource allocation
3. **Add more models**: Deploy multiple NIM models for different use cases
4. **Set up CI/CD**: Automate model deployment and updates
5. **Production hardening**: Implement security policies, network policies, and backup strategies
6. **Cost monitoring**: Set up billing alerts and usage tracking
7. **Batch processing**: Use CronJobs for scheduled model training/inference
