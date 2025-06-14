#!/bin/bash

# Prometheus to CSV Converter
# Collects metrics from a Prometheus endpoint and converts them to CSV format

set -euo pipefail

# Default values
ENDPOINT=""
OUTPUT_FILE=""
INTERVAL=10
DURATION=0
VERBOSE=false
INCLUDE_TIMESTAMP=true
FILTER_METRICS=""
HELP_METRICS=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    cat << EOF
Usage: $0 -e ENDPOINT [OPTIONS]

Collects Prometheus metrics from an HTTP endpoint and converts them to CSV format.

Required:
  -e, --endpoint URL        Prometheus metrics endpoint URL

Options:
  -o, --output FILE         Output CSV file (default: metrics_TIMESTAMP.csv)
  -i, --interval SECONDS    Collection interval in seconds (default: 10)
  -d, --duration SECONDS    Total collection duration in seconds (default: infinite)
  -f, --filter PATTERN     Filter metrics by name pattern (regex supported)
  -t, --no-timestamp        Don't include timestamp column in CSV
  -m, --help-metrics        Show available metrics from endpoint and exit
  -v, --verbose             Enable verbose output
  -h, --help                Show this help message

Examples:
  $0 -e http://localhost:8080/metrics
  $0 -e http://localhost:8080/metrics -o my_metrics.csv -i 5 -d 300
  $0 -e http://localhost:8080/metrics -f "cpu|memory" -v
  $0 -e http://localhost:8080/metrics --help-metrics

EOF
}

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${GREEN}[INFO]${NC} ${timestamp} - $message" >&2
            fi
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message" >&2
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" >&2
            ;;
        "DEBUG")
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - $message" >&2
            fi
            ;;
    esac
}

# Function to check dependencies
check_dependencies() {
    local deps=("curl" "awk" "grep" "sort")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "ERROR" "Missing required dependencies: ${missing[*]}"
        log "ERROR" "Please install the missing tools and try again"
        exit 1
    fi
}

# Function to validate endpoint
validate_endpoint() {
    log "INFO" "Validating endpoint: $ENDPOINT"
    
    if ! curl -s --connect-timeout 10 --max-time 30 "$ENDPOINT" > /dev/null; then
        log "ERROR" "Cannot reach endpoint: $ENDPOINT"
        log "ERROR" "Please check the URL and ensure the service is running"
        exit 1
    fi
    
    # Check if endpoint returns Prometheus format
    local content_type=$(curl -s -I --connect-timeout 10 --max-time 30 "$ENDPOINT" | grep -i "content-type" | head -1)
    log "DEBUG" "Content-Type: $content_type"
}

# Function to show available metrics
show_metrics() {
    log "INFO" "Fetching available metrics from: $ENDPOINT"
    
    local metrics=$(curl -s --connect-timeout 10 --max-time 30 "$ENDPOINT" | \
        grep -E "^[a-zA-Z_][a-zA-Z0-9_]*(\{.*\})?\s+" | \
        awk '{print $1}' | \
        sed 's/{.*//' | \
        sort -u)
    
    echo -e "\n${GREEN}Available metrics:${NC}"
    echo "$metrics" | nl -w3 -s'. '
    echo
    exit 0
}

# Function to fetch and parse metrics
fetch_metrics() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local epoch=$(date +%s)
    
    log "DEBUG" "Fetching metrics from: $ENDPOINT"
    
    local raw_metrics=$(curl -s --connect-timeout 10 --max-time 30 "$ENDPOINT")
    
    if [[ -z "$raw_metrics" ]]; then
        log "WARN" "No metrics received from endpoint"
        return 1
    fi
    
    # Parse metrics and convert to CSV format
    local parsed_metrics=$(echo "$raw_metrics" | awk -v timestamp="$timestamp" -v epoch="$epoch" -v filter="$FILTER_METRICS" '
    BEGIN {
        # Skip comments and empty lines
    }
    /^#/ { next }
    /^$/ { next }
    
    # Parse metric lines
    /^[a-zA-Z_][a-zA-Z0-9_]*/ {
        # Extract metric name, labels, and value
        metric_line = $0
        
        # Find the last space to separate value from the rest
        last_space = 0
        for (i = length(metric_line); i > 0; i--) {
            if (substr(metric_line, i, 1) == " ") {
                last_space = i
                break
            }
        }
        
        if (last_space > 0) {
            metric_part = substr(metric_line, 1, last_space - 1)
            value = substr(metric_line, last_space + 1)
            
            # Extract metric name and labels
            if (match(metric_part, /^([a-zA-Z_][a-zA-Z0-9_]*)(.*)/)) {
                metric_name = substr(metric_part, RSTART, RLENGTH)
                gsub(/\{.*/, "", metric_name)
                labels = metric_part
                gsub(/^[a-zA-Z_][a-zA-Z0-9_]*/, "", labels)
                
                # Apply filter if specified
                if (filter != "" && metric_name !~ filter) {
                    next
                }
                
                # Clean up labels
                gsub(/^\{/, "", labels)
                gsub(/\}$/, "", labels)
                
                # Output in CSV format
                printf "%s,%s,\"%s\",%s,%s\n", timestamp, epoch, metric_name, labels, value
            }
        }
    }'
    )
    
    echo "$parsed_metrics"
}

# Function to initialize CSV file
init_csv() {
    local header=""
    if [[ "$INCLUDE_TIMESTAMP" == "true" ]]; then
        header="timestamp,epoch,metric_name,labels,value"
    else
        header="metric_name,labels,value"
    fi
    
    echo "$header" > "$OUTPUT_FILE"
    log "INFO" "Initialized CSV file: $OUTPUT_FILE"
}

# Function to append metrics to CSV
append_metrics() {
    local metrics="$1"
    
    if [[ -n "$metrics" ]]; then
        if [[ "$INCLUDE_TIMESTAMP" == "false" ]]; then
            # Remove timestamp and epoch columns
            echo "$metrics" | awk -F',' '{print $3","$4","$5}' >> "$OUTPUT_FILE"
        else
            echo "$metrics" >> "$OUTPUT_FILE"
        fi
        
        local count=$(echo "$metrics" | wc -l)
        log "INFO" "Collected $count metrics"
    else
        log "WARN" "No metrics to append"
    fi
}

# Function to run collection loop
run_collection() {
    local start_time=$(date +%s)
    local iteration=0
    
    log "INFO" "Starting metrics collection..."
    log "INFO" "Endpoint: $ENDPOINT"
    log "INFO" "Output file: $OUTPUT_FILE"
    log "INFO" "Interval: ${INTERVAL}s"
    if [[ "$DURATION" -gt 0 ]]; then
        log "INFO" "Duration: ${DURATION}s"
    else
        log "INFO" "Duration: infinite (press Ctrl+C to stop)"
    fi
    
    # Initialize CSV file
    init_csv
    
    # Set up signal handler for graceful shutdown
    trap 'log "INFO" "Collection stopped by user"; exit 0' INT TERM
    
    while true; do
        iteration=$((iteration + 1))
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        log "DEBUG" "Collection iteration: $iteration (elapsed: ${elapsed}s)"
        
        # Check if duration limit reached
        if [[ "$DURATION" -gt 0 && "$elapsed" -ge "$DURATION" ]]; then
            log "INFO" "Duration limit reached (${DURATION}s)"
            break
        fi
        
        # Fetch and append metrics
        local metrics=$(fetch_metrics)
        if [[ $? -eq 0 ]]; then
            append_metrics "$metrics"
        fi
        
        # Wait for next interval
        if [[ "$DURATION" -eq 0 || "$elapsed" -lt "$DURATION" ]]; then
            log "DEBUG" "Waiting ${INTERVAL}s for next collection..."
            sleep "$INTERVAL"
        fi
    done
    
    log "INFO" "Collection completed. Results saved to: $OUTPUT_FILE"
    
    # Show summary
    local total_lines=$(wc -l < "$OUTPUT_FILE")
    local metric_lines=$((total_lines - 1))  # Subtract header
    log "INFO" "Total metrics collected: $metric_lines"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--endpoint)
            ENDPOINT="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -i|--interval)
            INTERVAL="$2"
            shift 2
            ;;
        -d|--duration)
            DURATION="$2"
            shift 2
            ;;
        -f|--filter)
            FILTER_METRICS="$2"
            shift 2
            ;;
        -t|--no-timestamp)
            INCLUDE_TIMESTAMP=false
            shift
            ;;
        -m|--help-metrics)
            HELP_METRICS=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$ENDPOINT" ]]; then
    log "ERROR" "Endpoint is required"
    usage
    exit 1
fi

# Set default output file if not specified
if [[ -z "$OUTPUT_FILE" ]]; then
    OUTPUT_FILE="metrics_$(date +%Y%m%d_%H%M%S).csv"
fi

# Check dependencies
check_dependencies

# Validate endpoint
validate_endpoint

# Show metrics if requested
if [[ "$HELP_METRICS" == "true" ]]; then
    show_metrics
fi

# Run the collection
run_collection 