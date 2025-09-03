#!/bin/bash

# GPU Metrics Configuration Script
# This script configures Prometheus to scrape GPU metrics from DCGM Exporter

set -e

# Load environment variables if .env file exists
if [ -f .env ]; then
    source .env
fi

# Default values (can be overridden by environment variables)
PROMETHEUS_NAMESPACE=${PROMETHEUS_NAMESPACE:-"prometheus"}
GPU_MONITORING_NAMESPACE=${GPU_MONITORING_NAMESPACE:-"gpu-monitoring"}
DCGM_SERVICE_NAME=${DCGM_SERVICE_NAME:-"dcgm-exporter"}

echo "Configuring GPU metrics scraping..."
echo "Prometheus namespace: $PROMETHEUS_NAMESPACE"
echo "GPU monitoring namespace: $GPU_MONITORING_NAMESPACE"
echo "DCGM service name: $DCGM_SERVICE_NAME"

# Check if Prometheus is running
echo "Checking Prometheus deployment..."
PROMETHEUS_NAME=$(kubectl get prometheus -n $PROMETHEUS_NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$PROMETHEUS_NAME" ]; then
    echo "Error: No Prometheus instance found in namespace $PROMETHEUS_NAMESPACE"
    exit 1
fi

echo "Found Prometheus instance: $PROMETHEUS_NAME"

# Check if DCGM Exporter is running
echo "Checking DCGM Exporter..."
DCGM_POD=$(kubectl get pods -n $GPU_MONITORING_NAMESPACE -l app=dcgm-exporter -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$DCGM_POD" ]; then
    echo "Error: No DCGM Exporter pod found in namespace $GPU_MONITORING_NAMESPACE"
    exit 1
fi

echo "Found DCGM Exporter pod: $DCGM_POD"

# Get the existing ConfigMap name that Prometheus is using
echo "Getting existing Prometheus configuration..."
EXISTING_CONFIG=$(kubectl get prometheus $PROMETHEUS_NAME -n $PROMETHEUS_NAMESPACE -o jsonpath='{.spec.additionalScrapeConfigs[0].name}' 2>/dev/null || echo "")

if [ -z "$EXISTING_CONFIG" ]; then
    echo "No existing additionalScrapeConfigs found, creating new configuration..."
    CONFIG_NAME="gpu-metrics-config"
else
    echo "Using existing ConfigMap: $EXISTING_CONFIG"
    CONFIG_NAME=$EXISTING_CONFIG
fi

# Update Prometheus to use our ConfigMap if it's not already configured
if [ "$CONFIG_NAME" != "gpu-metrics-config" ]; then
    echo "Updating Prometheus to use gpu-metrics-config..."
    kubectl patch prometheus $PROMETHEUS_NAME -n $PROMETHEUS_NAMESPACE --type='merge' -p='{"spec":{"additionalScrapeConfigs":[{"name":"gpu-metrics-config","key":"additional-scrape-configs.yaml"}]}}'
    CONFIG_NAME="gpu-metrics-config"
fi

# Create or update GPU metrics configuration
echo "Creating/updating GPU metrics configuration..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: $CONFIG_NAME
  namespace: $PROMETHEUS_NAMESPACE
data:
  additional-scrape-configs.yaml: |
    - job_name: gpu-metrics
      scrape_interval: 1s
      metrics_path: /metrics
      scheme: http
      kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
          - $GPU_MONITORING_NAMESPACE
      relabel_configs:
      - source_labels: [__meta_kubernetes_endpoints_name]
        action: drop
        regex: .*-node-feature-discovery-master
      - source_labels: [__meta_kubernetes_pod_node_name]
        action: replace
        target_label: kubernetes_node
EOF

echo "GPU metrics configuration updated in ConfigMap: $CONFIG_NAME"

# Wait for Prometheus to restart
echo "Waiting for Prometheus to restart..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n $PROMETHEUS_NAMESPACE --timeout=120s

echo "GPU metrics configuration completed!"
echo ""
echo "To verify the configuration:"
echo "1. Port forward Prometheus: kubectl port-forward service/kube-prometheus-stack-*-prometheus 9090:9090 -n $PROMETHEUS_NAMESPACE"
echo "2. Check targets: curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == \"gpu-metrics\")'"
echo "3. Check metrics: curl -s \"http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL\" | jq '.data.result'"