# Lab: Deploy NVIDIA NIM on DigitalOcean with GPU Monitoring

This lab guides you through deploying NVIDIA NIM on DigitalOcean Kubernetes (DOKS) with comprehensive GPU monitoring using Prometheus and Grafana.

## Prerequisites

- DigitalOcean account with billing enabled
- doctl CLI tool installed and configured
- kubectl installed
- Helm installed
- NVIDIA API key for NIM container access

## Step 0: Request GPU Access

DigitalOcean requires that you request access to GPU nodes before you can provision them.

1. Go to your DigitalOcean control panel
2. Submit a support ticket requesting access to GPU Droplets or nodes
3. In the request, explain your use case (e.g., "training AI models in a Kubernetes cluster")
4. Wait for confirmation from DigitalOcean

## Step 1: Create the Kubernetes Cluster with GPU Nodes

Create a cluster with GPU nodes. This command creates a cluster with a node pool containing a GPU.

```bash
# Set environment variables
export CLUSTER_NAME=nim-monitoring-cluster
export REGION=nyc1
export GPU_NODE_SIZE=gpu-2vcpu-8gb  # T4 GPU for NIM workloads

# Create the cluster with GPU node pool
doctl kubernetes cluster create ${CLUSTER_NAME} \
  --region ${REGION} \
  --version latest \
  --node-pool "name=gpu-worker-pool;size=${GPU_NODE_SIZE};count=1"

# Download cluster credentials
doctl kubernetes cluster kubeconfig save ${CLUSTER_NAME}

# Verify cluster connection
kubectl get nodes
```

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

## Step 3: Deploy NVIDIA NIM

Deploy the Llama 3.1 8B model using NIM with proper GPU resource allocation.

```bash
# Set NVIDIA API key
export NVIDIA_API_KEY="your-nvidia-api-key"

# Create namespace for NIM
kubectl create namespace nim

# Create secret for NVIDIA API key
kubectl create secret generic nim-api-key \
  --from-literal=api-key=${NVIDIA_API_KEY} \
  -n nim

# Deploy NIM with Llama 3.1 8B model
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
  name: llama-3-1-8b
  namespace: nim
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llama-3-1-8b
  template:
    metadata:
      labels:
        app: llama-3-1-8b
    spec:
      serviceAccountName: nim-sa
      nodeSelector:
        nvidia.com/gpu: "1"
      containers:
      - name: llama-3-1-8b
        image: nvcr.io/nim/llama-3.1-8b:latest
        ports:
        - containerPort: 8000
        resources:
          limits:
            nvidia.com/gpu: 1
        env:
        - name: NVIDIA_API_KEY
          valueFrom:
            secretKeyRef:
              name: nim-api-key
              key: api-key
---
apiVersion: v1
kind: Service
metadata:
  name: llama-3-1-8b-service
  namespace: nim
spec:
  selector:
    app: llama-3-1-8b
  ports:
  - port: 8000
    targetPort: 8000
  type: LoadBalancer
EOF

# Verify NIM deployment
kubectl get pods -n nim
kubectl get svc -n nim
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
EXTERNAL_IP=$(kubectl get svc llama-3-1-8b-service -n nim -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test NIM API
curl -X POST "http://$EXTERNAL_IP:8000/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-3.1-8b",
    "messages": [
      {"role": "user", "content": "Hello, how are you?"}
    ],
    "max_tokens": 100
  }'
```

While the API call is running, observe in Grafana:
- GPU utilization
- VRAM usage
- Temperature
- Power consumption
- Memory bandwidth

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
      app: llama-3-1-8b
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
      expr: DCGM_FI_DEV_GPU_TEMP > 80
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "GPU temperature is high"
        description: "GPU temperature is {{ \$value }}°C"
    - alert: HighGPUUtilization
      expr: DCGM_FI_DEV_GPU_UTIL > 95
      for: 10m
      labels:
        severity: info
      annotations:
        summary: "GPU utilization is very high"
        description: "GPU utilization is {{ \$value }}%"
EOF
```

## Step 9: Cleanup

To avoid unexpected charges, delete the cluster when finished:

```bash
doctl kubernetes cluster delete ${CLUSTER_NAME}
```

## Lab Objectives Achieved

This lab successfully demonstrates:

1. **GPU Cluster Management**: Creating and managing GPU-enabled Kubernetes clusters on DigitalOcean
2. **NVIDIA NIM Deployment**: Deploying AI models using NIM with proper resource allocation
3. **Monitoring & Observability**: Setting up comprehensive GPU monitoring with Prometheus and Grafana
4. **MLOps Best Practices**: Using Helm for reproducible deployments and Kubernetes for scaling
5. **Performance Analysis**: Monitoring GPU utilization, memory usage, and application performance

## Key Advantages of DigitalOcean Approach

- ✅ No GPU quota restrictions
- ✅ Predictable pricing (~$40-160/month for GPU nodes)
- ✅ Immediate GPU access after approval
- ✅ Simpler setup compared to GCP
- ✅ Comprehensive monitoring capabilities
- ✅ Easy scaling and resource management

## Next Steps

1. **Scale the deployment**: Add more GPU nodes to handle increased load
2. **Implement auto-scaling**: Use HPA and VPA for dynamic resource allocation
3. **Add more models**: Deploy additional NIM models for different use cases
4. **Set up CI/CD**: Automate model deployment and updates
5. **Production hardening**: Implement security policies, network policies, and backup strategies
