# Quick Dashboard Setup Guide

If the JSON import doesn't work, here's how to manually create the H100 NIM dashboard in Grafana.

## Prerequisites

- Grafana access: `http://localhost:3000`
- Prometheus data source configured
- DCGM Exporter running

## Step 1: Create New Dashboard

1. **Access Grafana**: `http://localhost:3000`
2. **Click**: "+" → "Dashboard"
3. **Set Dashboard Properties**:
   - **Title**: "H100 NIM Cluster Dashboard"
   - **Description**: "Comprehensive monitoring for H100 GPU cluster running NVIDIA NIM"
   - **Tags**: `h100`, `nim`, `gpu`, `monitoring`
   - **Time Range**: Last 15 minutes
   - **Refresh**: 30s

## Step 2: Add Dashboard Variables

### GPU Variable
1. **Click**: Dashboard Settings (gear icon) → Variables
2. **Click**: "Add variable"
3. **Configure**:
   - **Name**: `gpu`
   - **Type**: Query
   - **Data Source**: Prometheus
   - **Query**: `label_values(DCGM_FI_DEV_GPU_UTIL, gpu)`
   - **Multi-value**: ✓
   - **Include All**: ✓
   - **Default Value**: All

### Instance Variable
1. **Click**: "Add variable"
2. **Configure**:
   - **Name**: `instance`
   - **Type**: Query
   - **Data Source**: Prometheus
   - **Query**: `label_values(DCGM_FI_DEV_GPU_UTIL, instance)`
   - **Multi-value**: ✓
   - **Include All**: ✓
   - **Default Value**: All

## Step 3: Add Overview Panels

### Panel 1: Active GPUs (Stat)
1. **Click**: "Add panel"
2. **Visualization**: Stat
3. **Query**:
   ```promql
   count(DCGM_FI_DEV_GPU_UTIL)
   ```
4. **Display**:
   - **Title**: "Active GPUs"
   - **Unit**: short
   - **Color Mode**: Value
   - **Thresholds**: Green (0-1), Yellow (1-2), Red (2+)

### Panel 2: NIM Pods Ready (Stat)
1. **Click**: "Add panel"
2. **Visualization**: Stat
3. **Query**:
   ```promql
   count(kube_pod_status_ready{namespace="nim", condition="true"})
   ```
4. **Display**:
   - **Title**: "NIM Pods Ready"
   - **Unit**: short
   - **Color Mode**: Value
   - **Thresholds**: Red (0), Green (1+)

### Panel 3: Cluster Health (Stat)
1. **Click**: "Add panel"
2. **Visualization**: Stat
3. **Query**:
   ```promql
   count(kube_node_status_condition{condition="Ready", status="True"})
   ```
4. **Display**:
   - **Title**: "Cluster Health"
   - **Unit**: short
   - **Color Mode**: Value
   - **Thresholds**: Red (0), Green (1+)

### Panel 4: Active Alerts (Stat)
1. **Click**: "Add panel"
2. **Visualization**: Stat
3. **Query**:
   ```promql
   count(ALERTS{alertstate="firing"})
   ```
4. **Display**:
   - **Title**: "Active Alerts"
   - **Unit**: short
   - **Color Mode**: Value
   - **Thresholds**: Green (0), Yellow (1-4), Red (5+)

## Step 4: Add GPU Performance Panels

### Panel 5: GPU Utilization (TimeSeries)
1. **Click**: "Add panel"
2. **Visualization**: Time series
3. **Query A**:
   ```promql
   DCGM_FI_DEV_GPU_UTIL
   ```
   - **Legend**: `GPU {{gpu}}`
4. **Query B**:
   ```promql
   DCGM_FI_DEV_MEM_COPY_UTIL
   ```
   - **Legend**: `Memory {{gpu}}`
5. **Display**:
   - **Title**: "GPU Utilization"
   - **Unit**: percent
   - **Min**: 0, **Max**: 100
   - **Thresholds**: Green (0-80), Red (80-100)

### Panel 6: Temperature & Power (TimeSeries)
1. **Click**: "Add panel"
2. **Visualization**: Time series
3. **Query A**:
   ```promql
   DCGM_FI_DEV_GPU_TEMP
   ```
   - **Legend**: `Temp GPU {{gpu}}`
   - **Unit**: celsius
4. **Query B**:
   ```promql
   DCGM_FI_DEV_POWER_USAGE
   ```
   - **Legend**: `Power GPU {{gpu}}`
   - **Unit**: watt
5. **Display**:
   - **Title**: "Temperature & Power"
   - **Thresholds**: Green (0-70°C), Yellow (70-85°C), Red (85°C+)

### Panel 7: H100 Memory Usage (TimeSeries)
1. **Click**: "Add panel"
2. **Visualization**: Time series
3. **Query A**:
   ```promql
   DCGM_FI_DEV_FB_USED
   ```
   - **Legend**: `Used GPU {{gpu}}`
4. **Query B**:
   ```promql
   DCGM_FI_DEV_FB_FREE
   ```
   - **Legend**: `Free GPU {{gpu}}`
5. **Display**:
   - **Title**: "H100 Memory Usage (80GB HBM3)"
   - **Unit**: bytes
   - **Stack**: Yes
   - **Thresholds**: Green (0-60GB), Yellow (60-70GB), Red (70GB+)

### Panel 8: Clock Speeds (TimeSeries)
1. **Click**: "Add panel"
2. **Visualization**: Time series
3. **Query A**:
   ```promql
   DCGM_FI_DEV_SM_CLOCK
   ```
   - **Legend**: `SM Clock GPU {{gpu}}`
4. **Query B**:
   ```promql
   DCGM_FI_DEV_MEM_CLOCK
   ```
   - **Legend**: `Memory Clock GPU {{gpu}}`
5. **Display**:
   - **Title**: "Clock Speeds"
   - **Unit**: hertz

## Step 5: Add NIM Application Panels

### Panel 9: NIM API Request Rate (TimeSeries)
1. **Click**: "Add panel"
2. **Visualization**: Time series
3. **Query**:
   ```promql
   rate(http_requests_total{namespace="nim"}[5m])
   ```
   - **Legend**: `Requests/sec`
4. **Display**:
   - **Title**: "NIM API Request Rate"
   - **Unit**: reqps

### Panel 10: NIM Response Time (TimeSeries)
1. **Click**: "Add panel"
2. **Visualization**: Time series
3. **Query**:
   ```promql
   histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{namespace="nim"}[5m]))
   ```
   - **Legend**: `95th percentile`
4. **Display**:
   - **Title**: "NIM Response Time (95th percentile)"
   - **Unit**: seconds
   - **Thresholds**: Green (0-1s), Yellow (1-5s), Red (5s+)

### Panel 11: GPU Utilization by NIM (TimeSeries)
1. **Click**: "Add panel"
2. **Visualization**: Time series
3. **Query**:
   ```promql
   DCGM_FI_DEV_GPU_UTIL * on(pod) group_left(container) kube_pod_container_info{namespace="nim"}
   ```
   - **Legend**: `NIM Container`
4. **Display**:
   - **Title**: "GPU Utilization by NIM"
   - **Unit**: percent
   - **Min**: 0, **Max**: 100
   - **Thresholds**: Green (0-70%), Yellow (70-90%), Red (90-100%)

### Panel 12: NIM Error Rate (TimeSeries)
1. **Click**: "Add panel"
2. **Visualization**: Time series
3. **Query**:
   ```promql
   rate(http_requests_total{namespace="nim", status_code=~"5.."}[5m])
   ```
   - **Legend**: `Errors/sec`
4. **Display**:
   - **Title**: "NIM Error Rate (5xx)"
   - **Unit**: reqps
   - **Thresholds**: Green (0), Yellow (0.1), Red (1+)

## Step 6: Arrange Panels

### Overview Row (Row 1)
- **Panel 1**: Active GPUs (6x4, position 0,0)
- **Panel 2**: NIM Pods Ready (6x4, position 6,0)
- **Panel 3**: Cluster Health (6x4, position 12,0)
- **Panel 4**: Active Alerts (6x4, position 18,0)

### GPU Performance Row (Row 2)
- **Panel 5**: GPU Utilization (12x6, position 0,4)
- **Panel 6**: Temperature & Power (12x6, position 12,4)

### GPU Performance Row 2 (Row 3)
- **Panel 7**: H100 Memory Usage (12x6, position 0,10)
- **Panel 8**: Clock Speeds (12x6, position 12,10)

### NIM Application Row (Row 4)
- **Panel 9**: NIM API Request Rate (12x6, position 0,16)
- **Panel 10**: NIM Response Time (12x6, position 12,16)

### NIM Application Row 2 (Row 5)
- **Panel 11**: GPU Utilization by NIM (12x6, position 0,22)
- **Panel 12**: NIM Error Rate (12x6, position 12,22)

## Step 7: Save Dashboard

1. **Click**: "Save dashboard" (floppy disk icon)
2. **Name**: "H100 NIM Cluster Dashboard"
3. **Tags**: `h100`, `nim`, `gpu`, `monitoring`
4. **Click**: "Save"

## Troubleshooting

### No Data Issues
1. **Check Prometheus**: Verify data source is working
2. **Check DCGM**: Ensure DCGM Exporter is running
3. **Check Queries**: Test queries in Prometheus UI
4. **Check Time Range**: Ensure time range includes data

### Panel Issues
1. **Wrong Visualization**: Change panel type if needed
2. **Query Errors**: Check PromQL syntax
3. **Missing Metrics**: Verify metric names in Prometheus

### Variable Issues
1. **No Values**: Check if metrics exist
2. **Wrong Format**: Verify query syntax
3. **Refresh Issues**: Set appropriate refresh rate

## Quick Test Queries

Test these queries in Prometheus UI (`http://localhost:9090`) to verify data:

```promql
# GPU Utilization
DCGM_FI_DEV_GPU_UTIL

# GPU Temperature
DCGM_FI_DEV_GPU_TEMP

# GPU Memory Usage
DCGM_FI_DEV_FB_USED

# NIM Pods
kube_pod_status_ready{namespace="nim"}
```

This manual setup will create the same dashboard as the JSON import, but gives you full control over each panel and allows you to customize as needed.
