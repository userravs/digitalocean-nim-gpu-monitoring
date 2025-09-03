# Complete Monitoring Guide for DigitalOcean GPU Clusters

This comprehensive guide covers the complete setup and configuration of monitoring for your DigitalOcean Kubernetes cluster with NVIDIA NIM and GPU support.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Installation Steps](#installation-steps)
4. [Configuration](#configuration)
5. [Accessing Monitoring Tools](#accessing-monitoring-tools)
6. [Dashboard Setup](#dashboard-setup)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

## Prerequisites

**Refer to [Prerequisites section in README.md](../README.md#prerequisites)** for:
- DigitalOcean account setup
- doctl CLI installation and configuration
- kubectl and Helm installation
- Environment variables configuration

## Architecture Overview

Our monitoring stack consists of:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   DCGM Exporter │    │    Prometheus   │    │     Grafana     │
│   (GPU Metrics) │───▶│   (Data Store)  │───▶│   (Visualization)│
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  GPU Hardware   │    │  Alert Manager  │    │  Custom Dashboards│
│  (H100 Nodes)   │    │   (Alerts)      │    │  (NIM Metrics)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

**Components:**
- **DCGM Exporter**: Collects GPU metrics from NVIDIA hardware
- **Prometheus**: Time-series database for metrics storage
- **Grafana**: Visualization and dashboard platform
- **Alert Manager**: Handles alerting and notifications
- **Node Exporter**: System-level metrics collection

## Installation Steps

### Step 1: Install NVIDIA Device Plugin

**Refer to [Step 2: Install NVIDIA Device Plugin in README.md](../README.md#step-2-install-nvidia-device-plugin)**

### Step 2: Install DCGM Exporter

**Refer to [Step 3: Install DCGM Exporter in README.md](../README.md#step-3-install-dcgm-exporter-simplified-approach)**

### Step 3: Handle GPU Node Taints

**Refer to [Step 3.5: Handle GPU Node Taints in README.md](../README.md#step-35-handle-gpu-node-taints-optional---for-monitoring)**

### Step 4: Install Prometheus Stack

```bash
# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Deploy using standardized values file
helm install prometheus-community/kube-prometheus-stack \
   --create-namespace --namespace prometheus \
   --generate-name \
   --values prometheus-values.yaml
```

**What gets installed:**
- Prometheus (metrics collection and storage)
- Grafana (visualization and dashboards)
- Alert Manager (alerting and notifications)
- Node Exporter (system metrics)
- Kube State Metrics (Kubernetes metrics)
- Prometheus Operator (manages Prometheus instances)

### Step 5: Configure GPU Metrics

```bash
# Run the GPU metrics configuration script
./scripts/configure-gpu-metrics.sh
```

This script:
- Creates ConfigMap with GPU metrics scrape configuration
- Updates Prometheus to use the ConfigMap
- Waits for Prometheus to restart
- Verifies the configuration

**Note**: The default DCGM Exporter configuration provides basic GPU metrics. For advanced metrics like Tensor Core utilization, additional DCGM profiling configuration would be required.

## Configuration

### Prometheus Configuration

The `prometheus-values.yaml` file includes:

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    tolerations:
    - key: nvidia.com/gpu
      operator: Equal
      value: ""
      effect: NoSchedule
  service:
    type: NodePort
    nodePort: 30090

grafana:
  tolerations:
  - key: nvidia.com/gpu
    operator: Equal
    value: ""
    effect: NoSchedule
  adminPassword: prom-operator
  persistence:
    enabled: true
    size: 10Gi
```

### GPU Metrics Configuration

The GPU metrics are configured to scrape:
- **Job Name**: `gpu-metrics`
- **Scrape Interval**: 1 second
- **Target**: DCGM Exporter endpoints in `gpu-monitoring` namespace
- **Metrics**: All DCGM metrics (utilization, memory, temperature, power)

## Accessing Monitoring Tools

### Accessing Prometheus

**Method 1: Port Forwarding (Recommended)**
```bash
# Port forward Prometheus service
kubectl port-forward service/kube-prometheus-stack-*-prometheus 9090:9090 -n prometheus
```

**Method 2: NodePort (if configured)**
```bash
# Check if NodePort is configured
kubectl get svc -n prometheus | grep prometheus
```

**Access URL**: `http://localhost:9090`

### Accessing Grafana

**Method 1: Port Forwarding (Recommended)**
```bash
# Port forward Grafana service
kubectl port-forward service/kube-prometheus-stack-*-grafana 3000:80 -n prometheus
```

**Method 2: NodePort (if configured)**
```bash
# Patch Grafana service to NodePort
kubectl patch svc kube-prometheus-stack-*-grafana -n prometheus -p '{"spec":{"type":"NodePort","nodePort":32322}}'
```

**Access URL**: `http://localhost:3000`

**Default Credentials:**
- **Username**: `admin`
- **Password**: `prom-operator`

### Accessing Alert Manager

```bash
# Port forward Alert Manager service
kubectl port-forward service/kube-prometheus-stack-*-alertmanager 9093:9093 -n prometheus
```

**Access URL**: `http://localhost:9093`

## Dashboard Setup

### Importing DCGM Dashboard

1. **Access Grafana** using the methods above
2. **Navigate** to Dashboards → Import
3. **Enter Dashboard ID**: `12239`
4. **Select Data Source**: Prometheus
5. **Click Import**

**Alternative Import Method:**
1. Download the dashboard JSON from [DCGM Exporter GitHub](https://github.com/NVIDIA/dcgm-exporter/blob/main/grafana/dcgm-exporter-dashboard.json)
2. Go to Dashboards → Import
3. Click "Upload JSON file"
4. Select the downloaded JSON file
5. Choose Prometheus as data source
6. Click Import

### Creating Custom NIM Dashboards

**GPU Utilization Panel:**
```promql
DCGM_FI_DEV_GPU_UTIL{gpu="0"}
```

**Memory Utilization Panel:**
```promql
DCGM_FI_DEV_MEM_COPY_UTIL{gpu="0"}
```

**Temperature Panel:**
```promql
DCGM_FI_DEV_GPU_TEMP{gpu="0"}
```

**Power Usage Panel:**
```promql
DCGM_FI_DEV_POWER_USAGE{gpu="0"}
```

### Dashboard Variables

**GPU Variable:**
- **Name**: `gpu`
- **Type**: Query
- **Data Source**: Prometheus
- **Query**: `label_values(DCGM_FI_DEV_GPU_UTIL, gpu)`
- **Multi-value**: Yes
- **Include All**: Yes

**Namespace Variable:**
- **Name**: `namespace`
- **Type**: Query
- **Data Source**: Prometheus
- **Query**: `label_values(kube_pod_info, namespace)`
- **Multi-value**: Yes
- **Include All**: Yes

## Monitoring NIM Applications

### NIM-Specific Metrics

**Model Loading Status:**
```promql
kube_pod_status_ready{namespace="nim", condition="true"}
```

**GPU Memory Usage by NIM:**
```promql
DCGM_FI_DEV_MEM_COPY_UTIL{gpu="0"} * on(pod) group_left(container) kube_pod_container_info{namespace="nim"}
```

**NIM API Requests (if custom metrics available):**
```promql
rate(nim_api_requests_total[5m])
```

### Cost Optimization Metrics

**GPU Utilization Over Time:**
```promql
avg_over_time(DCGM_FI_DEV_GPU_UTIL[1h])
```

**Power Consumption Trends:**
```promql
avg_over_time(DCGM_FI_DEV_POWER_USAGE[1h])
```

**Idle Time Detection:**
```promql
time() - timestamp(DCGM_FI_DEV_GPU_UTIL < 5)
```

## Alerting Configuration

### Setting Up Alerts

**High GPU Utilization Alert:**
```promql
DCGM_FI_DEV_GPU_UTIL > 90
```
- **Duration**: 5m
- **Severity**: Warning
- **Summary**: "GPU utilization is above 90% for 5 minutes"

**High Temperature Alert:**
```promql
DCGM_FI_DEV_GPU_TEMP > 85
```
- **Duration**: 2m
- **Severity**: Critical
- **Summary**: "GPU temperature is above 85°C for 2 minutes"

**Low GPU Utilization Alert:**
```promql
DCGM_FI_DEV_GPU_UTIL < 5
```
- **Duration**: 10m
- **Severity**: Info
- **Summary**: "GPU is idle for 10 minutes - consider scaling down"

### Alert Configuration Steps

1. **Access Grafana** → Alerting → Alert Rules
2. **Click** "New Alert Rule"
3. **Configure** the alert parameters
4. **Set** notification channels
5. **Test** the alert

## Troubleshooting

### Common Issues

#### 1. GPU Metrics Not Scraped

**Symptoms:**
- No `gpu-metrics` job in Prometheus targets
- No DCGM metrics available in queries

**Diagnosis:**
```bash
# Check if DCGM Exporter is running
kubectl get pods -n gpu-monitoring

# Check DCGM Exporter logs
kubectl logs -n gpu-monitoring -l app=dcgm-exporter

# Verify DCGM metrics are available
kubectl port-forward service/dcgm-exporter 9400:9400 -n gpu-monitoring &
curl -s http://localhost:9400/metrics | grep DCGM_FI_DEV_GPU_UTIL
```

**Solution:**
```bash
# Run the GPU metrics configuration script
./scripts/configure-gpu-metrics.sh
```

#### 2. Prometheus Pods Not Starting

**Symptoms:**
- Prometheus pods in Pending or CrashLoopBackOff state

**Diagnosis:**
```bash
# Check pod events
kubectl describe pod -n prometheus -l app.kubernetes.io/name=prometheus

# Check if GPU taint is preventing scheduling
kubectl describe node | grep -A 5 Taints
```

**Solution:**
```bash
# Remove GPU taint (for single-node clusters)
kubectl taint nodes --all nvidia.com/gpu:NoSchedule-
```

#### 3. Grafana Access Issues

**Symptoms:**
- Cannot access Grafana web interface
- Port forwarding fails

**Diagnosis:**
```bash
# Check Grafana pod status
kubectl get pods -n prometheus -l app.kubernetes.io/name=grafana

# Check Grafana logs
kubectl logs -n prometheus -l app.kubernetes.io/name=grafana

# Check if port is already in use
lsof -i :3000
```

**Solution:**
```bash
# Kill existing port-forward processes
pkill -f "kubectl port-forward"

# Restart port forwarding
kubectl port-forward service/kube-prometheus-stack-*-grafana 3000:80 -n prometheus
```

#### 4. Performance Issues

**Symptoms:**
- Slow dashboard loading
- High resource usage

**Diagnosis:**
```bash
# Check resource usage
kubectl top pods -n prometheus

# Check Prometheus configuration
kubectl get prometheus -n prometheus -o yaml
```

**Solutions:**
- Optimize PromQL queries
- Reduce scrape intervals
- Increase resource limits
- Use query caching

### Verification Commands

**Check All Components:**
```bash
# Verify all monitoring pods are running
kubectl get pods -A | grep -E "(prometheus|grafana|dcgm)"

# Check services
kubectl get svc -A | grep -E "(prometheus|grafana|dcgm)"

# Verify GPU metrics are being scraped
kubectl port-forward service/kube-prometheus-stack-*-prometheus 9090:9090 -n prometheus &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "gpu-metrics")'
```

## Best Practices

### Dashboard Organization

- **Use folders** to organize dashboards by team/application
- **Standardize naming** conventions (e.g., "GPU Monitoring - Production")
- **Add descriptions** to dashboards and panels
- **Use tags** for easy searching

### Performance Optimization

- **Limit time ranges** in queries (use `[5m]` instead of `[1h]` when possible)
- **Use rate()** for counters instead of increase()
- **Set appropriate refresh intervals** (30s for real-time, 5m for trends)
- **Limit number of series** in queries

### Security

- **Change default passwords** immediately
- **Use RBAC** for dashboard access
- **Enable authentication** for production deployments
- **Regularly audit** dashboard permissions

### Maintenance

- **Backup dashboards** regularly
- **Version control** dashboard configurations
- **Monitor Grafana** itself for issues
- **Update Grafana** regularly for security patches

## Quick Reference

### Access URLs

| Service | Port Forward Command | Access URL | Default Credentials |
|---------|---------------------|------------|-------------------|
| Prometheus | `kubectl port-forward service/kube-prometheus-stack-*-prometheus 9090:9090 -n prometheus` | `http://localhost:9090` | None |
| Grafana | `kubectl port-forward service/kube-prometheus-stack-*-grafana 3000:80 -n prometheus` | `http://localhost:3000` | admin/prom-operator |
| Alert Manager | `kubectl port-forward service/kube-prometheus-stack-*-alertmanager 9093:9093 -n prometheus` | `http://localhost:9093` | None |

### Key Metrics

| Metric | Description | PromQL Query |
|--------|-------------|--------------|
| GPU Utilization | GPU compute utilization percentage | `DCGM_FI_DEV_GPU_UTIL` |
| Memory Utilization | GPU memory utilization percentage | `DCGM_FI_DEV_MEM_COPY_UTIL` |
| Temperature | GPU temperature in Celsius | `DCGM_FI_DEV_GPU_TEMP` |
| Power Usage | GPU power consumption in watts | `DCGM_FI_DEV_POWER_USAGE` |

### Useful Commands

```bash
# Check monitoring stack status
kubectl get pods -A | grep -E "(prometheus|grafana|dcgm)"

# Configure GPU metrics
./scripts/configure-gpu-metrics.sh

# Access Grafana
kubectl port-forward service/kube-prometheus-stack-*-grafana 3000:80 -n prometheus

# Access Prometheus
kubectl port-forward service/kube-prometheus-stack-*-prometheus 9090:9090 -n prometheus

# Check GPU metrics
curl -s "http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL" | jq '.data.result'
```

## Next Steps

- **Set up alerting** for critical metrics
- **Create custom dashboards** for specific use cases
- **Configure authentication** for production use
- **Set up dashboard backups** and version control
- **Monitor Grafana performance** and resource usage
- **Implement log aggregation** with tools like ELK stack or Loki

For advanced configurations and custom dashboards, refer to the [Grafana documentation](https://grafana.com/docs/) and [Prometheus documentation](https://prometheus.io/docs/).
