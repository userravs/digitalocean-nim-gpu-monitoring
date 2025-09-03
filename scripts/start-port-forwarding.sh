#!/bin/bash

# Port Forwarding Script for H100 NIM Cluster
# This script starts port forwarding for all monitoring services

set -e

echo "🚀 Starting port forwarding for H100 NIM Cluster services..."
echo ""

# Function to check if port is already in use
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
        echo "⚠️  Port $port is already in use. Stopping existing process..."
        lsof -ti:$port | xargs kill -9 2>/dev/null || true
        sleep 2
    fi
}

# Check and clear existing port forwarding
echo "🔍 Checking for existing port forwarding processes..."
check_port 9090
check_port 3000
check_port 8080
check_port 9400

# Kill any existing kubectl port-forward processes
pkill -f "kubectl port-forward" 2>/dev/null || true

echo "✅ Starting port forwarding services..."
echo ""

# Start Prometheus
echo "📊 Starting Prometheus port forwarding..."
kubectl port-forward service/kube-prometheus-stack-1756-prometheus 9090:9090 -n prometheus > /dev/null 2>&1 &
PROMETHEUS_PID=$!
sleep 2

# Start Grafana
echo "📈 Starting Grafana port forwarding..."
kubectl port-forward service/kube-prometheus-stack-1756880033-grafana 3000:80 -n prometheus > /dev/null 2>&1 &
GRAFANA_PID=$!
sleep 2

# Start NIM API
echo "🤖 Starting NIM API port forwarding..."
kubectl port-forward service/nim-service 8080:8080 -n nim > /dev/null 2>&1 &
NIM_PID=$!
sleep 2

# Start DCGM Exporter
echo "🎮 Starting DCGM Exporter port forwarding..."
kubectl port-forward service/dcgm-exporter 9400:9400 -n gpu-monitoring > /dev/null 2>&1 &
DCGM_PID=$!
sleep 2

echo ""
echo "🎉 Port forwarding started successfully!"
echo ""
echo "📋 Service Access URLs:"
echo "   Prometheus:    http://localhost:9090 (PID: $PROMETHEUS_PID)"
echo "   Grafana:       http://localhost:3000 (PID: $GRAFANA_PID)"
echo "   NIM API:       http://localhost:8080 (PID: $NIM_PID)"
echo "   DCGM Exporter: http://localhost:9400 (PID: $DCGM_PID)"
echo ""
echo "🔐 Grafana Credentials:"
echo "   Username: admin"
echo "   Password: prom-operator"
echo ""
echo "⏹️  To stop all port forwarding, run:"
echo "   pkill -f 'kubectl port-forward'"
echo ""
echo "🔍 To check if services are running:"
echo "   lsof -i :3000 -i :8080 -i :9090 -i :9400"
echo ""

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "🛑 Stopping port forwarding..."
    kill $PROMETHEUS_PID $GRAFANA_PID $NIM_PID $DCGM_PID 2>/dev/null || true
    pkill -f "kubectl port-forward" 2>/dev/null || true
    echo "✅ Port forwarding stopped."
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

echo "⏳ Port forwarding is active. Press Ctrl+C to stop all services."
echo ""

# Wait for user to stop
wait
