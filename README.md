# Lab: Deploy NVIDIA NIM on DigitalOcean with GPU Support

This lab guides you through deploying NVIDIA NIM on DigitalOcean Kubernetes (DOKS) with GPU support and proper authentication setup.

**✅ Current Status**: This lab has been tested and validated with DigitalOcean H100 GPU clusters. The DCGM Exporter approach has been simplified to work reliably with DigitalOcean's GPU node configurations.

## Quick Start Summary

**Correct Order of Steps:**
1. **Prerequisites** - Install doctl, kubectl, Helm, get NGC API key
2. **Step 1** - Create H100 GPU cluster on DigitalOcean
3. **Step 2** - Install NVIDIA Device Plugin for basic GPU support
4. **Step 3** - Install DCGM Exporter (simplified approach for GPU monitoring)
5. **Step 4** - Deploy NVIDIA NIM with proper authentication secrets
6. **Step 5** - Test NIM API functionality
7. **Step 6** - Cost optimization strategies
8. **Step 7** - Cleanup procedures

**Key Requirements:**
- Valid NGC API key in `.env` file as `NVIDIA_API_KEY`
- DCGM Exporter for GPU monitoring (simplified approach)
- Correct secret names: `NGC_API_KEY` (not `NGC_CLI_API_KEY`)
- DigitalOcean GPU nodes with `nvidia.com/gpu=1` label

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
vi .env
```

**Important**: Make sure to update the `NVIDIA_API_KEY` in the `.env` file with your actual NVIDIA API key before proceeding.


## Step 1: Create DigitalOcean H100 Cluster

```bash
# Load environment variables from .env file
source .env

# Create the cluster with H100 GPU node pool
doctl kubernetes cluster create ${CLUSTER_NAME} \
  --region ${REGION} \
  --version latest \
  --node-pool "name=${NODE_POOL_NAME};size=${GPU_NODE_SIZE};count=${NODE_POOL_COUNT}"

# Expected output and timing:
# Notice: Cluster is provisioning, waiting for cluster to be running
# .......................................................................................
# Notice: Cluster created, fetching credentials
# Notice: Adding cluster credentials to kubeconfig file found in "/Users/ravs/.kube/config"
# Notice: Setting current-context to do-tor1-nim-h100-cluster
# ID                                      Name                Region    Version        Auto Upgrade    Status     Node Pools
# 31e8a775-a347-4f17-aca6-871606d7bb25    nim-h100-cluster    tor1      1.33.1-do.3    false           running    h100-worker-pool
# doctl kubernetes cluster create ${CLUSTER_NAME} --region ${REGION} --version   0.19s user 0.08s system 0% cpu 7:49.82 total
#
# Note: Cluster creation typically takes 7-10 minutes for H100 GPU nodes

# Download cluster credentials
doctl kubernetes cluster kubeconfig save ${CLUSTER_NAME}

# Verify cluster connection
kubectl get nodes
```

## Step 2: Install NVIDIA Device Plugin

```bash
# Install NVIDIA device plugin
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.15.0/deployments/static/nvidia-device-plugin.yml

# Verify device plugin is running
kubectl get pods -n kube-system | grep nvidia

# Wait for GPU to become available (may take 30-60 seconds)
sleep 30

# Verify GPU is now available
kubectl get nodes -o json | jq '.items[0].status.allocatable | select(."nvidia.com/gpu")'
```

## Step 3: Install DCGM Exporter (Simplified Approach)

**Important**: DigitalOcean GPU nodes have specific configurations that make the full GPU Operator complex to deploy. We'll use a simplified approach with just DCGM Exporter, following DigitalOcean's recommended practices.

# Create namespace
kubectl create namespace gpu-monitoring

# Apply the DCGM Exporter deployment
kubectl apply -f dcgm-exporter-deployment.yaml

# Wait for DCGM Exporter to be ready
kubectl wait --for=condition=ready pod -l app=dcgm-exporter -n gpu-monitoring --timeout=300s

# Verify DCGM Exporter is running
kubectl get pods -n gpu-monitoring

# Test DCGM Exporter metrics
kubectl port-forward service/dcgm-exporter 9400:9400 -n gpu-monitoring &
curl localhost:9400/metrics | head -10

# Verify DCGM Exporter is working correctly
kubectl logs -n gpu-monitoring -l app=dcgm-exporter | grep "Starting webserver"



## Step 4: Deploy NVIDIA NIM (Optimized for H100)

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

# Create namespace for NIM
kubectl create namespace ${NIM_NAMESPACE}

# Fetch NIM LLM Helm Chart
helm fetch https://helm.ngc.nvidia.com/nim/charts/nim-llm-1.3.0.tgz \
  --username='$oauthtoken' \
  --password=$NVIDIA_API_KEY

# Configure Docker registry secret for nvcr.io
kubectl create secret docker-registry registry-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=$NVIDIA_API_KEY \
  -n ${NIM_NAMESPACE}

# Configure NGC API secret (note: pod expects NGC_API_KEY, not NGC_CLI_API_KEY)
kubectl create secret generic ngc-api \
  --from-literal=NGC_API_KEY=$NVIDIA_API_KEY \
  -n ${NIM_NAMESPACE}

# Launch NIM deployment
helm install my-nim nim-llm-1.3.0.tgz \
  -f nim_custom_value.yaml \
  --namespace ${NIM_NAMESPACE}

# Verify NIM pod is running
kubectl get pods -n ${NIM_NAMESPACE}

# Monitor pod startup (H100 models take longer to load)
kubectl logs -f my-nim-nim-llm-0 -n ${NIM_NAMESPACE}
```

## Step 5: Test NIM API

```bash
# Load environment variables from .env file
source .env

# Enable port forwarding to access NIM service locally
kubectl port-forward service/my-nim-nim-llm 8000:8000 -n ${NIM_NAMESPACE} &

# Wait a moment for port forwarding to establish
sleep 5

# Test NIM API
curl -X 'POST' \
  'http://localhost:8000/v1/chat/completions' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [
      {
        "content": "Hello, how are you?",
        "role": "user"
      }
    ],
    "model": "meta/llama3-8b-instruct",
    "max_tokens": 50,
    "temperature": 0.7
  }'
```

## Step 6: Cost Optimization

Since your H100 cluster costs $3.39/hour (~$2,500/month if running 24/7):

```bash
# Scale down when not in use
kubectl scale statefulset my-nim-nim-llm --replicas=0 -n ${NIM_NAMESPACE}

# Scale back up when needed
kubectl scale statefulset my-nim-nim-llm --replicas=1 -n ${NIM_NAMESPACE}

# Check resource usage
kubectl top nodes
kubectl top pods -n nim
```

## Step 7: Cleanup

**Important**: Your H100 cluster costs $3.39/hour. To avoid unexpected charges:

```bash
# Scale down (recommended for temporary pause)
kubectl scale statefulset my-nim-nim-llm --replicas=0 -n ${NIM_NAMESPACE}

# Delete cluster (WARNING: deletes all data)
doctl kubernetes cluster delete ${CLUSTER_NAME}
```

## Troubleshooting

### Common Issues

**ImagePullBackOff**: Authentication failure when pulling from `nvcr.io`
```bash
# Recreate secrets with correct variable names
source .env
kubectl delete secret registry-secret ngc-api -n ${NIM_NAMESPACE}
kubectl create secret docker-registry registry-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=$NVIDIA_API_KEY \
  -n ${NIM_NAMESPACE}
kubectl create secret generic ngc-api \
  --from-literal=NGC_API_KEY=$NVIDIA_API_KEY \
  -n ${NIM_NAMESPACE}
kubectl delete pod my-nim-nim-llm-0 -n ${NIM_NAMESPACE}
```

**GPU Not Available**: Install NVIDIA device plugin
```bash
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.15.0/deployments/static/nvidia-device-plugin.yml
```

**DCGM Exporter Pods Pending**: DigitalOcean GPU nodes have taints that prevent general workloads
```bash
# Check if GPU nodes have the required label
kubectl get nodes --show-labels | grep nvidia.com/gpu

# If the label is missing, add it
kubectl label node <your-gpu-node-name> nvidia.com/gpu=1

# Reinstall DCGM Exporter
kubectl delete -f dcgm-exporter-deployment.yaml
kubectl apply -f dcgm-exporter-deployment.yaml
```

**DCGM Exporter CSV Format Errors**: If you see CSV parsing errors, use the default configuration
```bash
# The deployment file should NOT include custom CSV configurations
# Use the default DCGM Exporter configuration as shown in the README
```

**DCGM Exporter Not Starting**: Check if the pod has proper tolerations and node selector
```bash
# Verify the deployment file has correct tolerations
kubectl describe pod <dcgm-exporter-pod-name> -n gpu-monitoring

# Check if GPU nodes have the required label
kubectl get nodes --show-labels | grep nvidia.com/gpu
```

**No GPU Metrics**: Ensure DCGM is properly initialized
```bash
# Check DCGM Exporter logs
kubectl logs -n gpu-monitoring -l app=dcgm-exporter

# Look for "DCGM successfully initialized!" message
```

**DCGM Exporter Not Created**: GPU operator doesn't recognize DigitalOcean GPU nodes
```bash
# Add required GPU labels to the node
kubectl label node h100-worker-pool-2aavk \
  nvidia.com/cuda.present=true \
  nvidia.com/gpu.count=1 \
  nvidia.com/mig.strategy=single \
  nvidia.com/gpu.product-name=NVIDIA-H100-80GB-PCIe \
  nvidia.com/gpu.product-full-name=NVIDIA-H100-80GB-PCIe \
  nvidia.com/gpu.memory=81920MiB \
  nvidia.com/gpu.family=Hopper \
  nvidia.com/gpu.pci.vendor=10de \
  nvidia.com/gpu.pci.device=2700

# Add NFD labels
kubectl label node h100-worker-pool-2aavk \
  feature.node.kubernetes.io/pci-10de.present=true \
  feature.node.kubernetes.io/gpu.count=1 \
  feature.node.kubernetes.io/gpu.family=Hopper \
  feature.node.kubernetes.io/gpu.memory=81920MiB
```

**DCGM Exporter Service Not Working**: Service selector doesn't match pod labels
```bash
# Add missing label to DCGM Exporter pod
kubectl label pod nvidia-dcgm-exporter-xxxxx app.kubernetes.io/name=dcgm-exporter -n gpu-operator

# Verify service has endpoints
kubectl get endpoints nvidia-dcgm-exporter -n gpu-operator
```

## Summary

This lab demonstrates deploying NVIDIA NIM on DigitalOcean H100 GPU clusters with:
- **GPU Cluster Management**: H100 with 80GB VRAM for large models
- **NVIDIA NIM Deployment**: Llama 3.1 8B with proper authentication
- **GPU Monitoring**: Simplified DCGM Exporter deployment following DigitalOcean best practices
- **Cost**: $3.39/hour (~$2,500/month for 24/7 usage)
- **Scaling**: Kubernetes-native scaling and resource management
- **Reliability**: Tested and validated approach that works with DigitalOcean's GPU node configurations

## Next Steps

- Experiment with larger models (Llama 3.1 405B, Mixtral 8x22B)
- Implement auto-scaling with HPA
- Deploy multiple NIM models for different use cases
- Set up CI/CD for automated deployments
