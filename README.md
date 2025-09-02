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

### Configure Environment Variables

This lab uses a `.env` file to manage configuration variables. A template `.env.example` file is provided.

```bash
# Copy the example file to create your .env file
cp .env.example .env

# Edit the .env file with your configuration
nano .env

# Or use your preferred editor
# vim .env
# code .env
```

**Important**: Make sure to update the `NVIDIA_API_KEY` in the `.env` file with your actual NVIDIA API key before proceeding.

### Verify NGC API Key
Before starting the lab, verify your NGC API key is valid:

```bash
# Test NGC API key authentication
curl -H "Authorization: Bearer YOUR_NGC_API_KEY" \
  https://api.ngc.nvidia.com/v2/models/nim/meta/llama3-8b-instruct

# If successful, you'll get a JSON response with model details
# If failed, you'll get a 401 error - update your API key
```

## Step 0: Validate GPU Availability and Request Access

### Check Available GPU Nodes in Your Region

Before creating a cluster, let's verify what GPU nodes are available in your target region:

```bash
# Check available GPU node sizes in Toronto region
doctl compute size list --format ID,Slug,Memory,CPUs,Disk,PriceMonthly,PriceHourly | grep gpu

# Check if H100 nodes are available in tor1 region
doctl compute size list --format ID,Slug,Memory,CPUs,Disk,PriceMonthly,PriceHourly | grep h100

# Verify Kubernetes cluster creation with GPU nodes in tor1
doctl kubernetes cluster create --help | grep -A 10 "node-pool"
```

### Expected Output for H100 Nodes:
```
gpu-h100x1-80gb            H100 GPU - 1X                    245760     20     720     2522.16          3.390000
```

### Request GPU Access (if needed)

DigitalOcean requires that you request access to GPU nodes before you can provision them.

1. Go to your DigitalOcean control panel
2. Submit a support ticket requesting access to GPU Droplets or nodes
3. In the request, explain your use case (e.g., "training AI models in a Kubernetes cluster")
4. Wait for confirmation from DigitalOcean

## Step 1: Create or Connect to DigitalOcean H100 Cluster

### Option A: Create a New H100 Cluster (Toronto Region)

If you need to create a new cluster with H100 GPU nodes:

```bash
# Load environment variables from .env file
source .env

# Verify environment variables are loaded
echo "Cluster Name: $CLUSTER_NAME"
echo "Region: $REGION"
echo "GPU Node Size: $GPU_NODE_SIZE"

# Create the cluster with H100 GPU node pool
doctl kubernetes cluster create ${CLUSTER_NAME} \
  --region ${REGION} \
  --version latest \
  --node-pool "name=${NODE_POOL_NAME};size=${GPU_NODE_SIZE};count=${NODE_POOL_COUNT}"

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
# Load environment variables from .env file
source .env

# Update CLUSTER_NAME in .env file to match your existing cluster
# Or override it here:
# export CLUSTER_NAME=your-existing-cluster-name

# Download cluster credentials
doctl kubernetes cluster kubeconfig save ${CLUSTER_NAME}

# Verify cluster connection and GPU node
kubectl get nodes
kubectl describe nodes | grep -A 5 "nvidia.com/gpu"

# Verify H100 GPU is available
kubectl get nodes -o json | jq '.items[].status.allocatable | select(."nvidia.com/gpu")'
```

**H100 Node Specifications** (`gpu-h100x1-80gb`):
- **GPU**: 1x NVIDIA H100 (Hopper Architecture)
- **VRAM**: 80 GB HBM3 Memory
- **System RAM**: 240 GiB
- **vCPU**: 20 cores
- **Boot Disk**: 720 GiB NVMe SSD
- **Scratch Disk**: 5 TiB NVMe SSD
- **Cost**: $3.39/hour (~$2,522/month if running 24/7)
- **Region**: Toronto (tor1)

**References:**
- [DigitalOcean GPU Droplets](https://www.digitalocean.com/products/gradient/gpu-droplets)
- [NVIDIA Hopper Architecture](https://www.nvidia.com/en-us/data-center/technologies/hopper-architecture/)

## Step 2: Install NVIDIA Device Plugin (Required for DigitalOcean GPU Support)

**Important**: DigitalOcean GPU nodes come with GPU labels but require manual installation of the NVIDIA device plugin to expose GPU resources to Kubernetes.

### Verify GPU Node Labels
First, let's verify that your DigitalOcean GPU node has the proper labels:

```bash
# Check GPU node labels
kubectl get nodes -o json | jq '.items[0].metadata.labels | select(."nvidia.com/gpu")'

# Expected output should show:
# "nvidia.com/gpu": "1"
# "doks.digitalocean.com/gpu-brand": "nvidia"
# "doks.digitalocean.com/gpu-model": "h100"
```

### Install NVIDIA Device Plugin
DigitalOcean GPU nodes need the NVIDIA device plugin to be installed manually:

```bash
# Install NVIDIA device plugin
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.15.0/deployments/static/nvidia-device-plugin.yml

# Verify device plugin is running
kubectl get pods -n kube-system | grep nvidia

# Wait for GPU to become available (may take 30-60 seconds)
sleep 30

# Verify GPU is now available in allocatable resources
kubectl get nodes -o json | jq '.items[0].status.allocatable | select(."nvidia.com/gpu")'
```

### Expected Output After Installation:
```json
{
  "cpu": "19850m",
  "ephemeral-storage": "684705487353",
  "hugepages-1Gi": "0",
  "hugepages-2Mi": "0",
  "memory": "241820054144",
  "nvidia.com/gpu": "1",
  "pods": "110"
}
```

### Troubleshooting Common Issues

**Issue**: Pods remain in `Pending` status with error `0/1 nodes are available: 1 Insufficient nvidia.com/gpu`

**Solution**: The NVIDIA device plugin is not installed or not running properly.

```bash
# Check if device plugin pod is running
kubectl get pods -n kube-system | grep nvidia

# If not running, check pod events
kubectl describe pod nvidia-device-plugin-daemonset-xxxxx -n kube-system

# Reinstall if needed
kubectl delete -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.15.0/deployments/static/nvidia-device-plugin.yml
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.15.0/deployments/static/nvidia-device-plugin.yml
```

**Issue**: GPU operator installation times out or fails

**Solution**: For DigitalOcean, the full GPU operator is often not necessary. The device plugin alone is sufficient for most workloads.

```bash
# Skip GPU operator installation and use device plugin only
# The device plugin provides basic GPU support without the full operator stack
```

## Step 3: Deploy NVIDIA NIM (Optimized for H100)

Deploy NVIDIA NIM using the official NGC Helm chart. We'll use Llama 3.1 8B which is a good starting point for testing.

**⚠️ IMPORTANT: Before proceeding, make sure you have:**
1. **Valid NVIDIA NGC API Key**: Update the `NVIDIA_API_KEY` in your `.env` file with your actual NGC API key
2. **NGC Account**: You need an NVIDIA NGC account with access to NIM models
3. **API Key Permissions**: Your API key must have access to `nvcr.io/nim/meta/` repositories

**To get your NGC API key:**
1. Go to [NVIDIA NGC](https://ngc.nvidia.com/)
2. Sign in to your account
3. Go to "API Keys" in your profile
4. Create a new API key or copy an existing one
5. Update your `.env` file: `NVIDIA_API_KEY=your-actual-api-key-here`

**Without a valid API key, the NIM deployment will fail with 401 Unauthorized errors.**

```bash
# Load environment variables from .env file
source .env

# Set NGC API key (update .env file with your actual NGC API key)
export NGC_CLI_API_KEY="${NVIDIA_API_KEY}"

# Verify NGC API key is set
if [ -z "$NGC_CLI_API_KEY" ]; then
    echo "Error: NGC_CLI_API_KEY is not set in .env file"
    exit 1
fi

# Create namespace for NIM
kubectl create namespace ${NIM_NAMESPACE}

# Fetch NIM LLM Helm Chart
helm fetch https://helm.ngc.nvidia.com/nim/charts/nim-llm-1.3.0.tgz \
  --username='$oauthtoken' \
  --password=$NGC_CLI_API_KEY

# Configure Docker registry secret for nvcr.io
kubectl create secret docker-registry registry-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=$NGC_CLI_API_KEY \
  -n ${NIM_NAMESPACE}

# Configure NGC API secret
kubectl create secret generic ngc-api \
  --from-literal=NGC_CLI_API_KEY=$NGC_CLI_API_KEY \
  -n ${NIM_NAMESPACE}

# Setup NIM Configuration for H100
cat <<EOF > nim_custom_value.yaml
image:
  repository: "nvcr.io/nim/meta/llama3-8b-instruct"  # Llama 3.1 8B (good starting point)
  tag: 1.0.0  # NIM version
model:
  ngcAPISecret: ngc-api  # NGC API secret name
persistence:
  enabled: true
  storageClass: "do-block-storage"  # DigitalOcean storage class
imagePullSecrets:
  - name: registry-secret  # Docker registry secret
EOF

# Launch NIM deployment
helm install my-nim nim-llm-1.3.0.tgz \
  -f nim_custom_value.yaml \
  --namespace ${NIM_NAMESPACE}

# Verify NIM pod is running
kubectl get pods -n ${NIM_NAMESPACE}
# Monitor pod startup (H100 models take longer to load)
kubectl logs -f my-nim-nim-llm-0 -n ${NIM_NAMESPACE}
```

## Step 4: Install Prometheus and Grafana for Monitoring

Install the monitoring stack to observe GPU performance and NIM metrics.

```bash
# Add Prometheus community Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Load environment variables from .env file
source .env

# Install Prometheus stack
helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace ${MONITORING_NAMESPACE} --create-namespace
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
# Load environment variables from .env file
source .env

# Enable port forwarding to access NIM service locally
kubectl port-forward service/my-nim-nim-llm 8000:8000 -n ${NIM_NAMESPACE} &

# Wait a moment for port forwarding to establish
sleep 5

# Test NIM API with a complex prompt to showcase H100 capabilities
curl -X 'POST' \
  'http://localhost:8000/v1/chat/completions' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [
      {
        "content": "You are a knowledgeable AI assistant with expertise in machine learning and GPU computing.",
        "role": "system"
      },
      {
        "content": "Explain the differences between transformer architectures and how they impact model performance. Provide a detailed technical analysis.",
        "role": "user"
      }
    ],
    "model": "meta/llama3-8b-instruct",
    "max_tokens": 500,
    "top_p": 1,
    "n": 1,
    "stream": false,
    "temperature": 0.7,
    "frequency_penalty": 0.0
  }'
```

While the API call is running, observe in Grafana:
- **GPU utilization** (should see moderate usage with 8B model)
- **VRAM usage** (expect ~8-12GB usage for Llama 3.1 8B)
- **Temperature** (H100 can handle up to 83°C)
- **Power consumption** (H100 can draw up to 700W)
- **Memory bandwidth** (H100 has 3.35 TB/s bandwidth)
- **Inference latency** (should be very fast with H100 for 8B model)

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
      app: my-nim-nim-llm
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
# Scale down NIM statefulset to 0 replicas when not needed
kubectl scale statefulset my-nim-nim-llm --replicas=0 -n ${NIM_NAMESPACE}

# Scale back up when needed
kubectl scale statefulset my-nim-nim-llm --replicas=1 -n ${NIM_NAMESPACE}
```

### Use Horizontal Pod Autoscaler (HPA)
```bash
# Install metrics-server if not already installed
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Create HPA for NIM statefulset
kubectl autoscale statefulset my-nim-nim-llm --cpu-percent=50 --min=0 --max=1 -n ${NIM_NAMESPACE}
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
kubectl scale statefulset my-nim-nim-llm --replicas=0 -n ${NIM_NAMESPACE}
kubectl scale deployment prometheus-stack-grafana --replicas=0 -n monitoring
kubectl scale deployment prometheus-stack-prometheus --replicas=0 -n monitoring

# The cluster will still cost $3.39/hour but with minimal resource usage
```

### Option 2: Delete Cluster (Only if you're completely done)
```bash
# WARNING: This will delete your entire cluster and all data
doctl kubernetes cluster delete ${CLUSTER_NAME}
```

## Issues Encountered and Solutions

### Problem 1: GPU Not Available in Kubernetes
**Issue**: Pods remained in `Pending` status with error `0/1 nodes are available: 1 Insufficient nvidia.com/gpu`

**Root Cause**: DigitalOcean GPU nodes have GPU labels but don't automatically expose GPU resources to Kubernetes. The NVIDIA device plugin must be installed manually.

**Solution**: Install the NVIDIA device plugin:
```bash
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.15.0/deployments/static/nvidia-device-plugin.yml
```

### Problem 2: GPU Operator Installation Timeout
**Issue**: GPU operator installation timed out or failed with context deadline exceeded

**Root Cause**: The full NVIDIA GPU operator is complex and may not be necessary for basic GPU workloads on DigitalOcean.

**Solution**: Use the device plugin only, which provides sufficient GPU support without the full operator stack.

### Problem 3: Persistent Volume Issues
**Issue**: Pods failed with `pod has unbound immediate PersistentVolumeClaims`

**Root Cause**: NIM requires persistent storage but no storage class was specified.

**Solution**: Add `storageClass: "do-block-storage"` to the NIM configuration.

### Problem 4: Model Selection
**Issue**: Initially tried to use Llama 3.1 70B which may be too large for initial testing

**Solution**: Start with Llama 3.1 8B for testing, then upgrade to larger models once everything is working.

### Problem 5: NGC API Key Authentication
**Issue**: Pod crashes with `401 Unauthorized` error and `CrashLoopBackOff` status

**Root Cause**: Missing or invalid NVIDIA NGC API key in the `.env` file

**Solution**: 
1. Get a valid NGC API key from [NVIDIA NGC](https://ngc.nvidia.com/)
2. Update `.env` file: `NVIDIA_API_KEY=your-actual-api-key-here`
3. Recreate the secret: `kubectl create secret generic ngc-api --from-literal=NGC_API_KEY=$NVIDIA_API_KEY -n nim`
4. Restart the pod: `kubectl delete pod my-nim-nim-llm-0 -n nim`

## Lab Objectives Achieved

This lab successfully demonstrates:

1. **GPU Cluster Management**: Creating and managing GPU-enabled Kubernetes clusters on DigitalOcean
2. **NVIDIA Device Plugin Setup**: Installing and configuring GPU support for DigitalOcean nodes
3. **NVIDIA NIM Deployment**: Deploying AI models using NIM with proper resource allocation
4. **Monitoring & Observability**: Setting up comprehensive GPU monitoring with Prometheus and Grafana
5. **MLOps Best Practices**: Using Helm for reproducible deployments and Kubernetes for scaling
6. **Performance Analysis**: Monitoring GPU utilization, memory usage, and application performance
7. **Troubleshooting**: Identifying and resolving common GPU deployment issues

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
