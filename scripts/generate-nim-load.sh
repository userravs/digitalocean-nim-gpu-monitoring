#!/bin/bash

# NIM Load Generator Script
# This script generates API calls to NIM to create metrics for dashboard monitoring

set -e

# Configuration
NIM_URL="http://localhost:8000"

# Check for help before setting variables
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    # Set dummy values for help display
    DURATION="--helps"
    RATE="10"
    CONCURRENT="5"
else
    DURATION=${1:-300}  # Default 5 minutes
    RATE=${2:-10}       # Default 10 requests per second
    CONCURRENT=${3:-5}  # Default 5 concurrent requests
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 NIM Load Generator Starting...${NC}"
echo -e "${YELLOW}Duration: ${DURATION}s | Rate: ${RATE} req/s | Concurrent: ${CONCURRENT}${NC}"
echo ""

# Function to check if NIM is accessible
check_nim() {
    echo -e "${BLUE}🔍 Checking NIM availability...${NC}"
    if ! curl -s "${NIM_URL}/v1/health/live" > /dev/null; then
        echo -e "${RED}❌ NIM is not accessible at ${NIM_URL}${NC}"
        echo -e "${YELLOW}Make sure port forwarding is active:${NC}"
        echo -e "kubectl port-forward service/my-nim-nim-llm 8000:8000 -n nim"
        exit 1
    fi
    echo -e "${GREEN}✅ NIM is accessible${NC}"
    echo ""
}

# Function to make a single API call
make_api_call() {
    local request_id=$1
    local start_time=$(date +%s.%N)
    
    # Random model selection
    local models=("llama2-7b" "llama2-13b" "llama2-70b" "codellama-7b" "codellama-13b")
    local model=${models[$RANDOM % ${#models[@]}]}
    
    # Random message content
    local messages=(
        "Hello, how are you?"
        "What is the capital of France?"
        "Explain quantum computing in simple terms"
        "Write a Python function to calculate fibonacci"
        "What are the benefits of renewable energy?"
        "Explain machine learning algorithms"
        "How does a neural network work?"
        "What is the difference between AI and ML?"
        "Write a simple REST API in Python"
        "Explain blockchain technology"
    )
    local message=${messages[$RANDOM % ${#messages[@]}]}
    
    # Random temperature for variety
    local temperature=$(awk -v min=0.1 -v max=1.0 'BEGIN{srand(); print min+rand()*(max-min)}')
    
    # Create request payload
    local payload=$(cat <<EOF
{
    "model": "${model}",
    "messages": [
        {
            "role": "user",
            "content": "${message}"
        }
    ],
    "temperature": ${temperature},
    "max_tokens": 100
}
EOF
)
    
    # Make the API call
    local response=$(curl -s -w "\n%{http_code}\n%{time_total}\n" \
        -X POST "${NIM_URL}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "${payload}" 2>/dev/null)
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    # Parse response
    local http_code=$(echo "$response" | tail -2 | head -1)
    local curl_time=$(echo "$response" | tail -1)
    local response_body=$(echo "$response" | sed '$d' | sed '$d')
    
    # Log the result
    if [[ "$http_code" == "200" ]]; then
        echo -e "${GREEN}✅ Request ${request_id}: ${model} | ${duration}s | ${http_code}${NC}"
    else
        echo -e "${RED}❌ Request ${request_id}: ${model} | ${duration}s | ${http_code}${NC}"
        echo -e "${YELLOW}Response: ${response_body}${NC}"
    fi
    
    # Return duration for statistics
    echo "$duration"
}

# Function to make concurrent requests
make_concurrent_requests() {
    local batch_id=$1
    local pids=()
    local durations=()
    
    echo -e "${BLUE}📦 Batch ${batch_id}: Starting ${CONCURRENT} concurrent requests...${NC}"
    
    # Start concurrent requests
    for ((i=1; i<=CONCURRENT; i++)); do
        local request_id="${batch_id}.${i}"
        make_api_call "$request_id" &
        pids+=($!)
    done
    
    # Wait for all requests to complete
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    echo -e "${GREEN}✅ Batch ${batch_id} completed${NC}"
    echo ""
}

# Function to generate load
generate_load() {
    local start_time=$(date +%s)
    local end_time=$((start_time + DURATION))
    local batch_count=0
    local total_requests=0
    
    echo -e "${BLUE}🔥 Starting load generation for ${DURATION} seconds...${NC}"
    echo ""
    
    while [[ $(date +%s) -lt $end_time ]]; do
        batch_count=$((batch_count + 1))
        total_requests=$((total_requests + CONCURRENT))
        
        make_concurrent_requests "$batch_count"
        
        # Sleep to maintain rate
        local sleep_time=$(echo "scale=3; 1/${RATE}" | bc -l)
        sleep "$sleep_time"
    done
    
    echo -e "${GREEN}🎉 Load generation completed!${NC}"
    echo -e "${YELLOW}Total batches: ${batch_count}${NC}"
    echo -e "${YELLOW}Total requests: ${total_requests}${NC}"
    echo -e "${YELLOW}Average rate: $(echo "scale=2; ${total_requests}/${DURATION}" | bc -l) req/s${NC}"
}

# Function to show usage
show_usage() {
    echo -e "${BLUE}Usage: $0 [duration] [rate] [concurrent]${NC}"
    echo ""
    echo -e "${YELLOW}Parameters:${NC}"
    echo -e "  duration   - Duration in seconds (default: 300)"
    echo -e "  rate       - Requests per second (default: 10)"
    echo -e "  concurrent - Concurrent requests per batch (default: 5)"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  $0                    # 5 minutes, 10 req/s, 5 concurrent"
    echo -e "  $0 600               # 10 minutes, 10 req/s, 5 concurrent"
    echo -e "  $0 300 20            # 5 minutes, 20 req/s, 5 concurrent"
    echo -e "  $0 300 10 10         # 5 minutes, 10 req/s, 10 concurrent"
    echo ""
}

# Function to cleanup
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Stopping load generation...${NC}"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Check for help
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

# Check prerequisites
if ! command -v bc &> /dev/null; then
    echo -e "${RED}❌ 'bc' command not found. Please install it.${NC}"
    exit 1
fi

# Check NIM availability
check_nim

# Start load generation
generate_load

echo ""
echo -e "${GREEN}🎯 Load generation completed!${NC}"
echo -e "${BLUE}Check your Grafana dashboard for updated metrics:${NC}"
echo -e "${YELLOW}  - NIM API Request Rate${NC}"
echo -e "${YELLOW}  - NIM Response Times${NC}"
echo -e "${YELLOW}  - NIM Error Rates${NC}"
echo -e "${YELLOW}  - GPU Utilization by NIM${NC}"
echo ""
echo -e "${BLUE}Dashboard URL: http://localhost:3000${NC}"
