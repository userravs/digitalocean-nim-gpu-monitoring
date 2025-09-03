# Custom Dashboard Guide for H100 NIM Clusters

This guide provides step-by-step instructions for creating custom Grafana dashboards specifically designed for DigitalOcean H100 GPU clusters running NVIDIA NIM applications.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Dashboard Architecture](#dashboard-architecture)
3. [Creating the Base Dashboard](#creating-the-base-dashboard)
4. [H100-Specific Panels](#h100-specific-panels)
5. [NIM Application Panels](#nim-application-panels)
6. [Modern Panel Types](#modern-panel-types)
7. [Dashboard Variables](#dashboard-variables)
8. [Alerting Configuration](#alerting-configuration)
9. [Export and Sharing](#export-and-sharing)
10. [Best Practices](#best-practices)

## Prerequisites

- **Grafana Access**: `http://localhost:3000` (admin/prom-operator)
- **Prometheus Data Source**: Configured and working
- **DCGM Exporter**: Running and providing metrics
- **NIM Application**: Deployed and operational
- **Basic Grafana Knowledge**: Understanding of panels and queries

## Dashboard Architecture

### Recommended Dashboard Structure

```
┌─────────────────────────────────────────────────────────────┐
│                    H100 NIM Cluster Dashboard              │
├─────────────────────────────────────────────────────────────┤
│  Overview Row                                              │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────┐ │
│  │ GPU Status  │ │ NIM Status  │ │ Cluster     │ │ Alerts  │ │
│  │ (Stat)      │ │ (Stat)      │ │ Health      │ │ (Stat)  │ │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────┘ │
├─────────────────────────────────────────────────────────────┤
│  GPU Performance Row                                        │
│  ┌─────────────────────┐ ┌─────────────────────┐            │
│  │ GPU Utilization     │ │ Memory Usage       │            │
│  │ (TimeSeries)        │ │ (TimeSeries)       │            │
│  └─────────────────────┘ └─────────────────────┘            │
│  ┌─────────────────────┐ ┌─────────────────────┐            │
│  │ Temperature & Power │ │ Clock Speeds       │            │
│  │ (TimeSeries)        │ │ (TimeSeries)       │            │
│  └─────────────────────┘ └─────────────────────┘            │
├─────────────────────────────────────────────────────────────┤
│  NIM Application Row                                        │
│  ┌─────────────────────┐ ┌─────────────────────┐            │
│  │ NIM API Requests   │ │ Model Performance  │            │
│  │ (TimeSeries)        │ │ (TimeSeries)       │            │
│  └─────────────────────┘ └─────────────────────┘            │
│  ┌─────────────────────┐ ┌─────────────────────┐            │
│  │ Response Times      │ │ Error Rates        │            │
│  │ (TimeSeries)        │ │ (TimeSeries)       │            │
│  └─────────────────────┘ └─────────────────────┘            │
├─────────────────────────────────────────────────────────────┤
│  System Health Row                                          │
│  ┌─────────────────────┐ ┌─────────────────────┐            │
│  │ Node Resources      │ │ Network I/O        │            │
│  │ (TimeSeries)        │ │ (TimeSeries)       │            │
│  └─────────────────────┘ └─────────────────────┘            │
│  ┌─────────────────────┐ ┌─────────────────────┐            │
│  │ Pod Status          │ │ Storage Usage       │            │
│  │ (Table)             │ │ (TimeSeries)       │            │
│  └─────────────────────┘ └─────────────────────┘            │
└─────────────────────────────────────────────────────────────┘
```

## Creating the Base Dashboard

### Step 1: Create New Dashboard

1. **Access Grafana**: `http://localhost:3000`
2. **Navigate**: Dashboards → New → Dashboard
3. **Set Dashboard Properties**:
   - **Title**: "H100 NIM Cluster Dashboard"
   - **Description**: "Comprehensive monitoring for H100 GPU cluster running NVIDIA NIM"
   - **Tags**: `h100`, `nim`, `gpu`, `monitoring`
   - **Time Range**: Last 15 minutes
   - **Refresh**: 30s

### Step 2: Configure Dashboard Variables

**GPU Variable:**
- **Name**: `gpu`
- **Type**: Query
- **Data Source**: Prometheus
- **Query**: `label_values(DCGM_FI_DEV_GPU_UTIL, gpu)`
- **Multi-value**: Yes
- **Include All**: Yes
- **Default Value**: All

**Instance Variable:**
- **Name**: `instance`
- **Type**: Query
- **Data Source**: Prometheus
- **Query**: `label_values(DCGM_FI_DEV_GPU_UTIL, instance)`
- **Multi-value**: Yes
- **Include All**: Yes
- **Default Value**: All

**Namespace Variable:**
- **Name**: `namespace`
- **Type**: Query
- **Data Source**: Prometheus
- **Query**: `label_values(kube_pod_info, namespace)`
- **Multi-value**: Yes
- **Include All**: Yes
- **Default Value**: All

## H100-Specific Panels

### 1. GPU Status Overview Panel

**Panel Type**: Stat
**Size**: 6x4
**Position**: Row 1, Column 1

**Query**:
```promql
count(DCGM_FI_DEV_GPU_UTIL{instance=~"${instance}", gpu=~"${gpu}"})
```

**Display**:
- **Title**: "Active GPUs"
- **Unit**: short
- **Color Mode**: Value
- **Thresholds**: 
  - Green: 0-1
  - Yellow: 1-2
  - Red: 2+

### 2. GPU Utilization Panel

**Panel Type**: TimeSeries
**Size**: 12x6
**Position**: Row 2, Column 1

**Query A**:
```promql
DCGM_FI_DEV_GPU_UTIL{instance=~"${instance}", gpu=~"${gpu}"}
```

**Display**:
- **Title**: "GPU Utilization"
- **Unit**: percent
- **Min**: 0
- **Max**: 100
- **Color**: Blue
- **Legend**: `GPU {{gpu}}`

**Query B** (Memory Utilization):
```promql
DCGM_FI_DEV_MEM_COPY_UTIL{instance=~"${instance}", gpu=~"${gpu}"}
```

### 3. H100 Temperature & Power Panel

**Panel Type**: TimeSeries
**Size**: 12x6
**Position**: Row 2, Column 2

**Query A** (Temperature):
```promql
DCGM_FI_DEV_GPU_TEMP{instance=~"${instance}", gpu=~"${gpu}"}
```

**Query B** (Power Usage):
```promql
DCGM_FI_DEV_POWER_USAGE{instance=~"${instance}", gpu=~"${gpu}"}
```

**Display**:
- **Title**: "Temperature & Power"
- **Temperature Unit**: celsius
- **Power Unit**: watt
- **Thresholds**:
  - Temperature: Green (0-70°C), Yellow (70-85°C), Red (85°C+)
  - Power: Green (0-300W), Yellow (300-400W), Red (400W+)

### 4. H100 Memory Usage Panel

**Panel Type**: TimeSeries
**Size**: 12x6
**Position**: Row 2, Column 3

**Query A** (Used Memory):
```promql
DCGM_FI_DEV_FB_USED{instance=~"${instance}", gpu=~"${gpu}"}
```

**Query B** (Free Memory):
```promql
DCGM_FI_DEV_FB_FREE{instance=~"${instance}", gpu=~"${gpu}"}
```

**Display**:
- **Title**: "H100 Memory Usage (80GB HBM3)"
- **Unit**: bytes (SI)
- **Stack**: Yes
- **Legend**: `Used`, `Free`

### 5. Clock Speeds Panel

**Panel Type**: TimeSeries
**Size**: 12x6
**Position**: Row 2, Column 4

**Query A** (SM Clock):
```promql
DCGM_FI_DEV_SM_CLOCK{instance=~"${instance}", gpu=~"${gpu}"}
```

**Query B** (Memory Clock):
```promql
DCGM_FI_DEV_MEM_CLOCK{instance=~"${instance}", gpu=~"${gpu}"}
```

**Display**:
- **Title**: "Clock Speeds"
- **Unit**: hertz
- **Legend**: `SM Clock`, `Memory Clock`

## NIM Application Panels

### 1. NIM Pod Status Panel

**Panel Type**: Stat
**Size**: 6x4
**Position**: Row 1, Column 2

**Query**:
```promql
count(kube_pod_status_ready{namespace="nim", condition="true"})
```

**Display**:
- **Title**: "NIM Pods Ready"
- **Unit**: short
- **Color Mode**: Value

### 2. NIM API Request Rate Panel

**Panel Type**: TimeSeries
**Size**: 12x6
**Position**: Row 3, Column 1

**Query** (if custom metrics available):
```promql
rate(nim_api_requests_total[5m])
```

**Alternative Query** (using HTTP metrics):
```promql
rate(http_requests_total{namespace="nim"}[5m])
```

**Display**:
- **Title**: "NIM API Request Rate"
- **Unit**: reqps (requests per second)
- **Legend**: `Requests/sec`

### 3. NIM Response Time Panel

**Panel Type**: TimeSeries
**Size**: 12x6
**Position**: Row 3, Column 2

**Query**:
```promql
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{namespace="nim"}[5m]))
```

**Display**:
- **Title**: "NIM Response Time (95th percentile)"
- **Unit**: seconds
- **Legend**: `95th percentile`

### 4. GPU Utilization by NIM Panel

**Panel Type**: TimeSeries
**Size**: 12x6
**Position**: Row 3, Column 3

**Query**:
```promql
DCGM_FI_DEV_GPU_UTIL{instance=~"${instance}", gpu=~"${gpu}"} * on(pod) group_left(container) kube_pod_container_info{namespace="nim"}
```

**Display**:
- **Title**: "GPU Utilization by NIM"
- **Unit**: percent
- **Legend**: `NIM Container`

### 5. NIM Error Rate Panel

**Panel Type**: TimeSeries
**Size**: 12x6
**Position**: Row 3, Column 4

**Query**:
```promql
rate(http_requests_total{namespace="nim", status_code=~"5.."}[5m])
```

**Display**:
- **Title**: "NIM Error Rate (5xx)"
- **Unit**: reqps
- **Legend**: `Errors/sec`

## Modern Panel Types

### TimeSeries Panel (Recommended)

**Advantages over old Graph panel:**
- Better performance
- Modern styling
- Improved tooltips
- Better legend handling
- Responsive design

**Configuration**:
- **Visualization**: TimeSeries
- **Display**: Lines, Points, Bars
- **Legend**: Table mode
- **Tooltip**: Shared crosshair

### Stat Panel

**Use Cases**:
- Overview metrics
- Current values
- Status indicators
- Summary statistics

**Configuration**:
- **Color Mode**: Value, Background
- **Text Mode**: Auto, Value, Value and name
- **Orientation**: Auto, Horizontal, Vertical

### Table Panel

**Use Cases**:
- Pod status
- Node information
- Alert history
- Metric details

**Configuration**:
- **Transform**: Organize fields
- **Column Alignment**: Auto, Left, Center, Right
- **Cell Display Mode**: Auto, Color text, Color background

## Dashboard Variables

### Advanced Variable Configuration

**Custom Variable for GPU Model**:
```promql
label_values(DCGM_FI_DEV_GPU_UTIL, modelName)
```

**Time Range Variable**:
- **Name**: `timeRange`
- **Type**: Custom
- **Values**: `1m,5m,15m,1h,6h,1d`
- **Default**: `15m`

**Refresh Rate Variable**:
- **Name**: `refreshRate`
- **Type**: Custom
- **Values**: `5s,10s,30s,1m,5m`
- **Default**: `30s`

## Alerting Configuration

### GPU Alerts

**High GPU Utilization**:
```promql
DCGM_FI_DEV_GPU_UTIL{instance=~"${instance}", gpu=~"${gpu}"} > 90
```
- **Duration**: 5m
- **Severity**: Warning
- **Summary**: "GPU utilization is above 90% for 5 minutes"

**High Temperature**:
```promql
DCGM_FI_DEV_GPU_TEMP{instance=~"${instance}", gpu=~"${gpu}"} > 85
```
- **Duration**: 2m
- **Severity**: Critical
- **Summary**: "GPU temperature is above 85°C for 2 minutes"

**Low GPU Utilization**:
```promql
DCGM_FI_DEV_GPU_UTIL{instance=~"${instance}", gpu=~"${gpu}"} < 5
```
- **Duration**: 10m
- **Severity**: Info
- **Summary**: "GPU is idle for 10 minutes"

### NIM Alerts

**NIM Pod Down**:
```promql
kube_pod_status_ready{namespace="nim", condition="false"} > 0
```
- **Duration**: 1m
- **Severity**: Critical
- **Summary**: "NIM pod is not ready"

**High Error Rate**:
```promql
rate(http_requests_total{namespace="nim", status_code=~"5.."}[5m]) > 0.1
```
- **Duration**: 2m
- **Severity**: Warning
- **Summary**: "NIM error rate is above 10%"

## Export and Sharing

### Export Dashboard

1. **Navigate**: Dashboard → Settings → JSON Model
2. **Copy JSON**: Save to file
3. **Version Control**: Commit to repository

### Share Dashboard

1. **Public URL**: Settings → Links → Public URL
2. **Snapshot**: Settings → Snapshots → Create
3. **Export**: Settings → Export → Save JSON

### Dashboard JSON Template

```json
{
  "dashboard": {
    "title": "H100 NIM Cluster Dashboard",
    "description": "Comprehensive monitoring for H100 GPU cluster running NVIDIA NIM",
    "tags": ["h100", "nim", "gpu", "monitoring"],
    "time": {
      "from": "now-15m",
      "to": "now"
    },
    "refresh": "30s",
    "templating": {
      "list": [
        {
          "name": "gpu",
          "type": "query",
          "datasource": "Prometheus",
          "query": "label_values(DCGM_FI_DEV_GPU_UTIL, gpu)",
          "multi": true,
          "includeAll": true
        }
      ]
    },
    "panels": [
      // Panel definitions will be added here
    ]
  }
}
```

## Best Practices

### Performance Optimization

1. **Query Optimization**:
   - Use appropriate time ranges
   - Limit series with labels
   - Use rate() for counters
   - Avoid expensive aggregations

2. **Panel Configuration**:
   - Limit number of series per panel
   - Use appropriate refresh rates
   - Enable query caching
   - Use time series panels for better performance

3. **Dashboard Design**:
   - Group related panels
   - Use consistent color schemes
   - Provide clear titles and descriptions
   - Include helpful tooltips

### H100-Specific Considerations

1. **Memory Monitoring**:
   - H100 has 80GB HBM3 memory
   - Monitor both used and free memory
   - Set appropriate thresholds

2. **Temperature Monitoring**:
   - H100 thermal limits
   - Monitor both GPU and memory temperature
   - Set alerts for thermal throttling

3. **Power Monitoring**:
   - H100 power consumption patterns
   - Monitor efficiency metrics
   - Track power vs performance

### NIM-Specific Considerations

1. **Model Loading**:
   - Monitor model load times
   - Track model memory usage
   - Alert on model failures

2. **API Performance**:
   - Monitor request rates
   - Track response times
   - Monitor error rates

3. **Resource Utilization**:
   - GPU utilization by NIM
   - Memory usage patterns
   - CPU utilization

### Maintenance

1. **Regular Updates**:
   - Update dashboard variables
   - Review and adjust thresholds
   - Add new metrics as needed

2. **Documentation**:
   - Document custom queries
   - Maintain panel descriptions
   - Update alert configurations

3. **Testing**:
   - Test dashboard with different time ranges
   - Verify alert functionality
   - Validate metric accuracy

## Troubleshooting

### Common Issues

1. **No Data**:
   - Check Prometheus data source
   - Verify metric names
   - Check time range

2. **Slow Queries**:
   - Optimize PromQL queries
   - Reduce time range
   - Use more specific labels

3. **Missing Metrics**:
   - Verify DCGM Exporter is running
   - Check metric availability
   - Review DCGM configuration

### Debugging Queries

1. **Test in Prometheus**:
   - Use Prometheus UI to test queries
   - Verify metric names and labels
   - Check data availability

2. **Use Grafana Explore**:
   - Test queries in Explore mode
   - Validate data sources
   - Debug query syntax

3. **Check Logs**:
   - Review DCGM Exporter logs
   - Check Prometheus logs
   - Monitor Grafana logs

This custom dashboard guide provides a comprehensive framework for creating modern, H100-optimized monitoring dashboards specifically designed for NVIDIA NIM applications.
