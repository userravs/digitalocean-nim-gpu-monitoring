# Grafana Setup and Configuration for GPU Monitoring

This guide covers setting up and configuring Grafana for comprehensive GPU monitoring on your DigitalOcean Kubernetes cluster with NVIDIA NIM.

## Prerequisites

**Refer to [Prerequisites section in README.md](../README.md#prerequisites)** for:
- DigitalOcean account setup
- doctl CLI installation and configuration
- kubectl and Helm installation
- Environment variables configuration

## Prerequisites for Grafana

**Refer to [docs/prometheus-setup.md](prometheus-setup.md)** for:
- Prometheus stack deployment (includes Grafana installation)
- DCGM Exporter setup
- GPU metrics collection configuration

**Note**: Grafana is automatically installed as part of the `kube-prometheus-stack` Helm chart. See **Step 5: Deploy Prometheus Stack** in the Prometheus setup guide for the installation command.

## Accessing Grafana

### 1. Port Forwarding Setup

```bash
# Port forward Grafana service to your local machine
kubectl port-forward service/kube-prometheus-stack-*-grafana 3000:80 -n prometheus
```

**Note**: Run this in a separate terminal window and keep it running while using Grafana.

### 2. Access Grafana Web Interface

Open your browser and navigate to: `http://localhost:3000`

### 3. Default Login Credentials

- **Username**: `admin`
- **Password**: `prom-operator`

**Security Note**: These are default credentials. Consider changing the password for production deployments.

## Initial Grafana Configuration

### 1. Change Default Password

1. After first login, Grafana will prompt you to change the password
2. Enter a strong password and confirm
3. Click "Save"

### 2. Configure Data Sources

Grafana should automatically detect Prometheus as a data source. If not:

1. Go to **Configuration** → **Data Sources**
2. Click **Add data source**
3. Select **Prometheus**
4. Configure:
   - **URL**: `http://prometheus-kube-prometheus-stack-*-prometheus:9090`
   - **Access**: Server (default)
5. Click **Save & Test**

## Importing GPU Monitoring Dashboards

### 1. DCGM Exporter Dashboard

The DCGM Exporter provides a comprehensive GPU monitoring dashboard:

#### **Option A: Import by Dashboard ID**
1. Go to **Dashboards** → **Import**
2. Enter Dashboard ID: `12239`
3. Click **Load**
4. Select your Prometheus data source
5. Click **Import**

#### **Option B: Import from JSON**
1. Go to **Dashboards** → **Import**
2. Click **Upload JSON file**
3. Download the dashboard from [DCGM Exporter GitHub](https://github.com/NVIDIA/dcgm-exporter/blob/main/grafana/dcgm-exporter-dashboard.json)
4. Upload the JSON file
5. Select your Prometheus data source
6. Click **Import**

### 2. Custom NIM Monitoring Dashboard

Create a custom dashboard for NVIDIA NIM monitoring:

#### **Dashboard Setup**
1. Go to **Dashboards** → **New** → **Dashboard**
2. Click **Add new panel**
3. Configure the following panels:

#### **GPU Utilization Panel**
```promql
# GPU Utilization
DCGM_FI_DEV_GPU_UTIL{gpu="0"}

# Panel Configuration:
- Title: "GPU Utilization"
- Unit: "percent"
- Min: 0, Max: 100
- Thresholds: 
  - Green: 0-70
  - Yellow: 70-90
  - Red: 90-100
```

#### **Memory Utilization Panel**
```promql
# GPU Memory Utilization
DCGM_FI_DEV_MEM_COPY_UTIL{gpu="0"}

# Panel Configuration:
- Title: "GPU Memory Utilization"
- Unit: "percent"
- Min: 0, Max: 100
```

#### **Temperature Panel**
```promql
# GPU Temperature
DCGM_FI_DEV_GPU_TEMP{gpu="0"}

# Panel Configuration:
- Title: "GPU Temperature"
- Unit: "celsius"
- Thresholds:
  - Green: 0-70
  - Yellow: 70-85
  - Red: 85-100
```

#### **Power Usage Panel**
```promql
# GPU Power Usage
DCGM_FI_DEV_POWER_USAGE{gpu="0"}

# Panel Configuration:
- Title: "GPU Power Usage"
- Unit: "watt"
```

#### **NIM API Response Time Panel**
```promql
# NIM API Response Time (if you have custom metrics)
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])

# Panel Configuration:
- Title: "NIM API Response Time"
- Unit: "seconds"
```

### 3. Cluster Overview Dashboard

Create a cluster-wide monitoring dashboard:

#### **Node Metrics**
```promql
# CPU Usage
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory Usage
100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100)

# Disk Usage
100 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100)
```

#### **Pod Metrics**
```promql
# Running Pods by Namespace
count(container_start_time_seconds) by (namespace)

# Pod Restart Count
increase(kube_pod_container_status_restarts_total[1h]) by (pod, namespace)
```

## Advanced Grafana Configuration

### 1. Dashboard Variables

Add variables for better dashboard flexibility:

#### **GPU Variable**
1. Go to **Dashboard Settings** → **Variables**
2. Click **Add variable**
3. Configure:
   - **Name**: `gpu`
   - **Type**: Query
   - **Data source**: Prometheus
   - **Query**: `label_values(DCGM_FI_DEV_GPU_UTIL, gpu)`
   - **Multi-value**: Yes
   - **Include All option**: Yes

#### **Namespace Variable**
1. Add another variable:
   - **Name**: `namespace`
   - **Type**: Query
   - **Data source**: Prometheus
   - **Query**: `label_values(kube_pod_info, namespace)`
   - **Multi-value**: Yes
   - **Include All option**: Yes

### 2. Alerting Configuration

Set up alerts for critical GPU metrics:

#### **High GPU Utilization Alert**
1. Go to **Alerting** → **Alert Rules**
2. Click **New Alert Rule**
3. Configure:
   - **Rule name**: "High GPU Utilization"
   - **Query**: `DCGM_FI_DEV_GPU_UTIL > 90`
   - **Duration**: 5m
   - **Severity**: Warning
   - **Summary**: "GPU utilization is above 90% for 5 minutes"

#### **High Temperature Alert**
1. Create another alert rule:
   - **Rule name**: "High GPU Temperature"
   - **Query**: `DCGM_FI_DEV_GPU_TEMP > 85`
   - **Duration**: 2m
   - **Severity**: Critical
   - **Summary**: "GPU temperature is above 85°C for 2 minutes"

### 3. Dashboard Permissions

Configure dashboard access:

1. Go to **Dashboard Settings** → **Permissions**
2. Click **Add Permission**
3. Configure:
   - **Role**: Viewer/Editor/Admin
   - **User/Team**: Select appropriate users
   - **Permission**: View/Edit/Admin

## Monitoring NIM Applications

### 1. NIM-Specific Metrics

Monitor your NVIDIA NIM deployment:

#### **Model Loading Status**
```promql
# Check if NIM pods are ready
kube_pod_status_ready{namespace="nim", condition="true"}
```

#### **GPU Memory Usage by NIM**
```promql
# GPU memory used by NIM pods
DCGM_FI_DEV_MEM_COPY_UTIL{gpu="0"} * on(pod) group_left(container) kube_pod_container_info{namespace="nim"}
```

#### **NIM API Requests**
```promql
# If you have custom NIM metrics
rate(nim_api_requests_total[5m])
```

### 2. Cost Optimization Dashboard

Create a dashboard for cost monitoring:

#### **GPU Utilization Over Time**
```promql
# Average GPU utilization per hour
avg_over_time(DCGM_FI_DEV_GPU_UTIL[1h])
```

#### **Power Consumption Trends**
```promql
# Average power usage per hour
avg_over_time(DCGM_FI_DEV_POWER_USAGE[1h])
```

#### **Idle Time Detection**
```promql
# Time GPU is idle (utilization < 5%)
time() - timestamp(DCGM_FI_DEV_GPU_UTIL < 5)
```

## Troubleshooting Grafana

### 1. Access Issues

```bash
# Check if Grafana pod is running
kubectl get pods -n prometheus -l app.kubernetes.io/name=grafana

# Check Grafana logs
kubectl logs -n prometheus -l app.kubernetes.io/name=grafana

# Verify service exists
kubectl get svc -n prometheus | grep grafana
```

### 2. Data Source Issues

```bash
# Check Prometheus connectivity
kubectl port-forward service/kube-prometheus-stack-*-prometheus 9090:9090 -n prometheus &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "gpu-metrics")'
```

### 3. Dashboard Issues

```bash
# Check if GPU metrics are available
kubectl port-forward service/kube-prometheus-stack-*-prometheus 9090:9090 -n prometheus &
curl -s "http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL" | jq '.data.result'
```

### 4. Performance Issues

```bash
# Check Grafana resource usage
kubectl top pods -n prometheus -l app.kubernetes.io/name=grafana

# Check Grafana configuration
kubectl get configmap -n prometheus | grep grafana
```

## Best Practices

### 1. Dashboard Organization

- **Use folders** to organize dashboards by team/application
- **Standardize naming** conventions (e.g., "GPU Monitoring - Production")
- **Add descriptions** to dashboards and panels
- **Use tags** for easy searching

### 2. Performance Optimization

- **Limit time ranges** in queries (use `[5m]` instead of `[1h]` when possible)
- **Use rate()** for counters instead of increase()
- **Set appropriate refresh intervals** (30s for real-time, 5m for trends)
- **Limit number of series** in queries

### 3. Security

- **Change default passwords** immediately
- **Use RBAC** for dashboard access
- **Enable authentication** for production deployments
- **Regularly audit** dashboard permissions

### 4. Maintenance

- **Backup dashboards** regularly
- **Version control** dashboard configurations
- **Monitor Grafana** itself for issues
- **Update Grafana** regularly for security patches

## Next Steps

- **Set up alerting** for critical metrics
- **Create custom dashboards** for specific use cases
- **Configure authentication** for production use
- **Set up dashboard backups** and version control
- **Monitor Grafana performance** and resource usage

For advanced configurations and custom dashboards, refer to the [Grafana documentation](https://grafana.com/docs/).
