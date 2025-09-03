# Port Forwarding Guide

This guide provides the commands needed to access Prometheus, Grafana, and NIM services running in your DigitalOcean Kubernetes cluster from your local machine.

## Prerequisites

- `kubectl` configured and connected to your DOKS cluster
- Access to the cluster with appropriate permissions

## Quick Access Commands

### 1. Access Prometheus (Port 9090)

```bash
# Forward Prometheus service to local port 9090
kubectl port-forward service/kube-prometheus-stack-1756-prometheus 9090:9090 -n prometheus
```

**Access URL:** http://localhost:9090

### 2. Access Grafana (Port 3000)

```bash
# Forward Grafana service to local port 3000
kubectl port-forward service/kube-prometheus-stack-1756880033-grafana 3000:80 -n prometheus
```

**Access URL:** http://localhost:3000

**Default Credentials:**
- Username: `admin`
- Password: `prom-operator`

### 3. Access NIM API (Port 8080)

```bash
# Forward NIM service to local port 8080
kubectl port-forward service/nim-service 8080:8080 -n nim
```

**Access URL:** http://localhost:8080

### 4. Access DCGM Exporter (Port 9400)

```bash
# Forward DCGM Exporter service to local port 9400
kubectl port-forward service/dcgm-exporter 9400:9400 -n gpu-monitoring
```

**Access URL:** http://localhost:9400

## Background Execution

To run these commands in the background and keep them active:

```bash
# Start all port forwarding in background
kubectl port-forward service/kube-prometheus-stack-1756-prometheus 9090:9090 -n prometheus &
kubectl port-forward service/kube-prometheus-stack-1756880033-grafana 3000:80 -n prometheus &
kubectl port-forward service/nim-service 8080:8080 -n nim &
kubectl port-forward service/dcgm-exporter 9400:9400 -n gpu-monitoring &
```

## Service Discovery

If you need to find the exact service names, use these commands:

```bash
# List all services in prometheus namespace
kubectl get services -n prometheus

# List all services in nim namespace
kubectl get services -n nim

# List all services in gpu-monitoring namespace
kubectl get services -n gpu-monitoring
```

## Verification Commands

Check if port forwarding is working:

```bash
# Check if ports are listening
netstat -tulpn | grep -E ':(3000|8080|9090|9400)'

# Or using lsof
lsof -i :3000
lsof -i :8080
lsof -i :9090
lsof -i :9400
```

## Troubleshooting

### Port Already in Use

If you get "address already in use" errors:

```bash
# Kill existing port forwarding processes
pkill -f "kubectl port-forward"

# Or kill specific ports
lsof -ti:3000 | xargs kill -9
lsof -ti:8080 | xargs kill -9
lsof -ti:9090 | xargs kill -9
lsof -ti:9400 | xargs kill -9
```

### Service Not Found

If services are not found, verify they exist:

```bash
# Check if services exist
kubectl get services --all-namespaces | grep -E "(prometheus|grafana|nim|dcgm)"

# Check service details
kubectl describe service kube-prometheus-stack-1756-prometheus -n prometheus
kubectl describe service kube-prometheus-stack-1756880033-grafana -n prometheus
kubectl describe service nim-service -n nim
kubectl describe service dcgm-exporter -n gpu-monitoring
```

### Connection Refused

If you get connection refused:

```bash
# Check if pods are running
kubectl get pods -n prometheus
kubectl get pods -n nim
kubectl get pods -n gpu-monitoring

# Check pod logs
kubectl logs -n prometheus deployment/kube-prometheus-stack-1756-prometheus
kubectl logs -n prometheus deployment/kube-prometheus-stack-1756880033-grafana
kubectl logs -n nim deployment/nim-deployment
kubectl logs -n gpu-monitoring deployment/dcgm-exporter
```

## One-Liner Script

Create a script to start all port forwarding:

```bash
#!/bin/bash
# save as start-port-forwarding.sh

echo "Starting port forwarding for all services..."

# Start Prometheus
kubectl port-forward service/kube-prometheus-stack-1756-prometheus 9090:9090 -n prometheus &
PROMETHEUS_PID=$!

# Start Grafana
kubectl port-forward service/kube-prometheus-stack-1756880033-grafana 3000:80 -n prometheus &
GRAFANA_PID=$!

# Start NIM
kubectl port-forward service/nim-service 8080:8080 -n nim &
NIM_PID=$!

# Start DCGM Exporter
kubectl port-forward service/dcgm-exporter 9400:9400 -n gpu-monitoring &
DCGM_PID=$!

echo "Port forwarding started:"
echo "Prometheus: http://localhost:9090 (PID: $PROMETHEUS_PID)"
echo "Grafana: http://localhost:3000 (PID: $GRAFANA_PID)"
echo "NIM API: http://localhost:8080 (PID: $NIM_PID)"
echo "DCGM Exporter: http://localhost:9400 (PID: $DCGM_PID)"

# Wait for user to stop
echo "Press Ctrl+C to stop all port forwarding"
wait
```

Make it executable and run:

```bash
chmod +x start-port-forwarding.sh
./start-port-forwarding.sh
```

## Stop Port Forwarding

To stop all port forwarding:

```bash
# Kill all kubectl port-forward processes
pkill -f "kubectl port-forward"

# Or kill specific processes by PID (if you saved them)
kill $PROMETHEUS_PID $GRAFANA_PID $NIM_PID $DCGM_PID
```

## Service URLs Summary

| Service | Local URL | Namespace | Description |
|---------|-----------|-----------|-------------|
| Prometheus | http://localhost:9090 | prometheus | Metrics collection and querying |
| Grafana | http://localhost:3000 | prometheus | Dashboard visualization |
| NIM API | http://localhost:8080 | nim | NVIDIA NIM application API |
| DCGM Exporter | http://localhost:9400 | gpu-monitoring | GPU metrics endpoint |

## Security Notes

- Port forwarding creates a direct tunnel to your cluster
- Only use on trusted networks
- Consider using VPN or SSH tunneling for remote access
- Monitor active connections regularly
- Stop port forwarding when not needed

## Next Steps

After starting port forwarding:

1. **Access Grafana**: Import your dashboards
2. **Access Prometheus**: Verify metrics are being collected
3. **Test NIM API**: Verify application is responding
4. **Check DCGM**: Verify GPU metrics are available

For persistent access, consider setting up:
- Ingress controllers
- Load balancers
- VPN connections
- SSH tunnels
