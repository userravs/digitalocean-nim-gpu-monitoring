# Setting up Prometheus with GPU Monitoring on DigitalOcean

This guide covers setting up a complete Prometheus monitoring stack with GPU metrics collection for your DigitalOcean Kubernetes cluster with NVIDIA NIM.

## Prerequisites

**Refer to [Prerequisites section in README.md](../README.md#prerequisites)** for:
- DigitalOcean account setup
- doctl CLI installation and configuration
- kubectl and Helm installation
- Environment variables configuration

## Cluster Setup

**Refer to [Step 1: Create DigitalOcean H100 Cluster in README.md](../README.md#step-1-create-digitalocean-h100-cluster)** for cluster creation.

## GPU Device Plugin Installation

**Refer to [Step 2: Install NVIDIA Device Plugin in README.md](../README.md#step-2-install-nvidia-device-plugin)** for basic GPU support setup.

## DCGM Exporter Setup

**Refer to [Step 3: Install DCGM Exporter in README.md](../README.md#step-3-install-dcgm-exporter-simplified-approach)** for the simplified DCGM Exporter deployment approach.

## Setting up Prometheus Stack

### 1. Add Prometheus Helm Repository

```bash
# Add the Prometheus community Helm repository
helm repo add prometheus-community \
   https://prometheus-community.github.io/helm-charts

# Update Helm repositories
helm repo update
```

### 2. Search for Available Charts

```bash
# Search for available prometheus charts
helm search repo kube-prometheus
```

### 3. Use Standardized Values File

This repository includes a pre-configured `prometheus-values.yaml` file with all necessary settings for DigitalOcean GPU clusters:

```bash
# View the standardized values file
cat prometheus-values.yaml
```

The file includes:
- GPU tolerations for all components
- NodePort service configuration
- GPU metrics scrape configuration
- Persistence settings for Grafana
- Proper service monitor selector configuration

### 4. Configuration Details

The `prometheus-values.yaml` file includes all necessary configurations:

**GPU Tolerations**: All components have tolerations for the `nvidia.com/gpu:NoSchedule` taint
**Service Configuration**: Prometheus is configured as NodePort on port 30090
**GPU Metrics Scraping**: Automatic discovery of DCGM Exporter in the `gpu-monitoring` namespace
**Persistence**: Grafana data is persisted with 10Gi storage

### 4.1. GPU Metrics Configuration

The `prometheus-values.yaml` file automatically configures GPU metrics scraping:

```yaml
additionalScrapeConfigs:
- job_name: gpu-metrics
  scrape_interval: 1s
  metrics_path: /metrics
  scheme: http
  kubernetes_sd_configs:
  - role: endpoints
    namespaces:
      names:
      - gpu-monitoring
  relabel_configs:
  - source_labels: [__meta_kubernetes_endpoints_name]
    action: drop
    regex: .*-node-feature-discovery-master
  - source_labels: [__meta_kubernetes_pod_node_name]
    action: replace
    target_label: kubernetes_node
```

This configuration:
- Discovers DCGM Exporter endpoints in the `gpu-monitoring` namespace
- Scrapes metrics every 1 second for real-time monitoring
- Adds node labels for better metric organization
- Filters out irrelevant endpoints

### 5. Deploy Prometheus Stack

**⚠️ IMPORTANT: GPU Node Taint Issue**

DigitalOcean H100 GPU nodes have a taint `nvidia.com/gpu:NoSchedule` that prevents non-GPU workloads from being scheduled. The `prometheus-values.yaml` file includes all necessary tolerations.

**Option A: Remove GPU Taint (Recommended for single-node clusters)**
```bash
# Remove the GPU taint to allow mixed workloads
kubectl taint nodes --all nvidia.com/gpu:NoSchedule-
```

**Option B: Use Standardized Values File (Recommended)**
```bash
# Deploy using the pre-configured values file
helm install prometheus-community/kube-prometheus-stack \
   --create-namespace --namespace prometheus \
   --generate-name \
   --values prometheus-values.yaml
```

**Option C: Custom Values (Advanced users)**
```bash
# Inspect and customize if needed
helm inspect values prometheus-community/kube-prometheus-stack > custom-prometheus-values.yaml
# Edit custom-prometheus-values.yaml as needed
helm install prometheus-community/kube-prometheus-stack \
   --create-namespace --namespace prometheus \
   --generate-name \
   --values custom-prometheus-values.yaml
```

**Recommended Approach**: Use Option B with the standardized values file for consistent deployments.

### 6. Verify Deployment

You should see output similar to:
```
NAME: kube-prometheus-stack-1637791640
LAST DEPLOYED: Wed Nov 24 22:07:22 2021
NAMESPACE: prometheus
STATUS: deployed
REVISION: 1
NOTES:
kube-prometheus-stack has been installed. Check its status by running:
  kubectl --namespace prometheus get pods -l "release=kube-prometheus-stack-1637791640"
```

Check the status of all pods:
```bash
kubectl get pods -A
```

Expected Prometheus stack pods:
- `alertmanager-kube-prometheus-stack-*-alertmanager-0`
- `kube-prometheus-stack-*-operator-*`
- `kube-prometheus-stack-*-grafana-*`
- `kube-prometheus-stack-*-kube-state-metrics-*`
- `kube-prometheus-stack-*-prometheus-node-exporter-*`
- `prometheus-kube-prometheus-stack-*-prometheus-0`

**Verify GPU Metrics Discovery:**
```bash
# Check if Prometheus is scraping GPU metrics
kubectl port-forward service/kube-prometheus-stack-*-prometheus 9090:9090 -n prometheus &
PF_PID=$!
sleep 5
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "gpu-metrics")'
kill $PF_PID
```

You should see DCGM Exporter endpoints being scraped by the `gpu-metrics` job.

**Note**: If GPU metrics are not showing up, the additional scrape configuration may need to be applied manually. See the troubleshooting section below.

## Using Grafana

**For comprehensive Grafana setup and configuration, see [docs/grafana-setup.md](grafana-setup.md)**

### Quick Access

```bash
# Port forward Grafana service (in a separate terminal)
kubectl port-forward service/kube-prometheus-stack-*-grafana 3000:80 -n prometheus
```

Open your browser to `http://localhost:3000`

**Default credentials:**
- Username: `admin`
- Password: `prom-operator`

## Viewing GPU Metrics

### 1. Access Prometheus UI

```bash
# Port forward Prometheus service (in a separate terminal)
kubectl port-forward service/kube-prometheus-stack-*-prometheus 9090:9090 -n prometheus
```

Open your browser to `http://localhost:9090`

### 2. Verify GPU Metrics

In the Prometheus query interface, search for GPU metrics:
- `DCGM_FI_DEV_GPU_UTIL` - GPU utilization
- `DCGM_FI_DEV_MEM_COPY_UTIL` - Memory utilization
- `DCGM_FI_DEV_GPU_TEMP` - GPU temperature
- `DCGM_FI_DEV_POWER_USAGE` - Power usage

### 3. Check Service Discovery

Navigate to **Status** → **Targets** in Prometheus to verify that the `gpu-metrics` job is discovering your DCGM Exporter endpoints.

## Monitoring Running Applications

### 1. View NIM Application Metrics

**Refer to [Step 4: Deploy NVIDIA NIM in README.md](../README.md#step-4-deploy-nvidia-nim-optimized-for-h100)** for NIM deployment.

Once NIM is running, you can monitor:
- GPU utilization during inference
- Memory usage patterns
- Power consumption
- Temperature trends

### 2. Create Custom Dashboards

In Grafana, create custom dashboards to monitor:
- NIM API response times
- GPU utilization during different model loads
- Resource usage patterns over time
- Cost optimization metrics

## Troubleshooting

### 1. DCGM Exporter Not Scraped

If Prometheus is not scraping DCGM metrics:
```bash
# Check if DCGM Exporter is running
kubectl get pods -n gpu-monitoring

# Check DCGM Exporter logs
kubectl logs -n gpu-monitoring -l app=dcgm-exporter

# Verify service exists
kubectl get svc -n gpu-monitoring
```

### 2. Prometheus Targets Not Up

```bash
# Check Prometheus operator logs
kubectl logs -n prometheus -l app.kubernetes.io/name=prometheus-operator

# Check Prometheus server logs
kubectl logs -n prometheus -l app=prometheus
```

### 3. Grafana Access Issues

```bash
# Check Grafana pod status
kubectl get pods -n prometheus -l app.kubernetes.io/name=grafana

# Check Grafana logs
kubectl logs -n prometheus -l app.kubernetes.io/name=grafana
```

### 4. Port Forwarding Issues

```bash
# Check for existing port-forward processes
ps aux | grep "kubectl port-forward"

# Kill port-forward processes if needed
pkill -f "kubectl port-forward"

# Check if ports are in use
lsof -i :3000  # Grafana
lsof -i :9090  # Prometheus
```

### 5. GPU Metrics Not Scraped

If GPU metrics are not being collected by Prometheus:

```bash
# Check if DCGM Exporter is providing metrics
kubectl port-forward service/dcgm-exporter 9400:9400 -n gpu-monitoring &
sleep 3
curl -s http://localhost:9400/metrics | grep DCGM_FI_DEV_GPU_UTIL | head -1
kill $!

# Check Prometheus additional scrape configs
kubectl get prometheus -n prometheus -o yaml | grep -A 10 additionalScrapeConfigs

# Apply GPU metrics configuration using the provided script
./scripts/configure-gpu-metrics.sh
```

## Cleanup

**Refer to [Step 7: Cleanup in README.md](../README.md#step-7-cleanup)** for cluster cleanup procedures.

To remove only the Prometheus stack:
```bash
# List Helm releases
helm list -n prometheus

# Uninstall Prometheus stack
helm uninstall <release-name> -n prometheus

# Delete namespace
kubectl delete namespace prometheus
```

## Next Steps

- **Refer to [Step 5: Test NIM API in README.md](../README.md#step-5-test-nim-api)** to test your NIM deployment
- **Refer to [Step 6: Cost Optimization in README.md](../README.md#step-6-cost-optimization)** for cost management strategies
- Set up alerting rules in Prometheus for GPU utilization thresholds
- Configure Grafana alerts for critical metrics
- Implement log aggregation with tools like ELK stack or Loki
