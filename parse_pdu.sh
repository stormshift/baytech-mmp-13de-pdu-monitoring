#!/bin/bash
set -euo pipefail

# Parse BayTech MMP-14DE PDU data and output Nagios performance data
# Usage: ./parse_pdu.sh <data_file> <PDU-NAME> [AMPS|KWH|TEMP|VOLTAGE|WATTAGE]

PDU_NAME="${2}" 
DATA_KIND="${3:-AMPS}"

if [[ -z "$PDU_NAME" ]]; then
    echo "FAILED - PDU name is required"
    exit 3
fi

DATA_FILE="${1}.${PDU_NAME}"

if [[ ! -r "$DATA_FILE" && "$DATA_FILE" != "/dev/stdin" ]]; then
    echo "FAILED - Cannot read file: $DATA_FILE"
    exit 3
fi

MAX_AGE=900  # 15 minutes in seconds

FILE_AGE=$(( $(date +%s) - $(stat -c %Y "$DATA_FILE") ))  # macOS

if (( FILE_AGE >= MAX_AGE )); then
    echo "FAILED - File is stale ($FILE_AGE seconds old)"
    exit 3
fi

# Read the entire file content
DATA=$(cat "$DATA_FILE")

# Initialize performance data string
PERFDATA=""

# Extract Total kW-h
KWH=$(echo "$DATA" | grep -E "^Total kW-h:" | sed 's/Total kW-h:[[:space:]]*//' | tr -d '[:space:]')
if [[ -n "$KWH" && "$DATA_KIND" == "KWH" ]]; then
    PERFDATA="${PERFDATA} total_kwh=${KWH},"
fi

# # Extract Internal Temperature
TEMP=$(echo "$DATA" | grep -E "^Int\. Temp:" | awk '{print $3}' )
if [[ -n "$TEMP" && "$DATA_KIND" == "TEMP" ]]; then
    CELSIUS=$(echo "scale=1; ($TEMP - 32) * 5 / 9" | bc);
    PERFDATA="${PERFDATA} internal_temp_celsius=${CELSIUS},"
fi

# Extract Circuit Breaker data (Input A, CKT1, CKT2)
while IFS= read -r line; do
    if [[ "$line" =~ \|[[:space:]]*([^|]+)[[:space:]]*\|[[:space:]]*([0-9.]+)[[:space:]]*Amps[[:space:]]*\|[[:space:]]*([0-9.]+)[[:space:]]*Amps[[:space:]]*\| ]]; then
        NAME=$(echo "${BASH_REMATCH[1]}" | xargs | tr ' ' '_' | tr '[:upper:]' '[:lower:]')
        TRUE_RMS="${BASH_REMATCH[2]}"
        PEAK_RMS="${BASH_REMATCH[3]}"
        
        if [[ "$NAME" =~ ^(input_a|ckt[0-9]+)$ && "$DATA_KIND" == "AMPS" ]]; then
            PERFDATA="${PERFDATA} ${NAME}_true_rms_current=${TRUE_RMS},"
            PERFDATA="${PERFDATA} ${NAME}_peak_rms_current=${PEAK_RMS},"
        fi
    fi
done <<< "$DATA"

# Extract Circuit Group data (M1-M4) with voltage, power, VA
while IFS= read -r line; do
    if [[ "$line" =~ \|[[:space:]]*Circuit[[:space:]]+(M[0-9]+)[[:space:]]*\|[[:space:]]*([0-9.]+)[[:space:]]*Amps[[:space:]]*\|[[:space:]]*([0-9.]+)[[:space:]]*Amps[[:space:]]*\|[[:space:]]*([0-9.]+)[[:space:]]*Volts[[:space:]]*\|[[:space:]]*([0-9]+)[[:space:]]*Watts[[:space:]]*\|[[:space:]]*([0-9]+)[[:space:]]*VA[[:space:]]*\| ]]; then
        CIRCUIT=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')
        TRUE_RMS="${BASH_REMATCH[2]}"
        PEAK_RMS="${BASH_REMATCH[3]}"
        VOLTAGE="${BASH_REMATCH[4]}"
        POWER="${BASH_REMATCH[5]}"
        VA="${BASH_REMATCH[6]}"
        
        if [[ "$DATA_KIND" == "AMPS" ]]; then
            PERFDATA="${PERFDATA} circuit_${CIRCUIT}_true_rms_current=${TRUE_RMS},"
            PERFDATA="${PERFDATA} circuit_${CIRCUIT}_peak_rms_current=${PEAK_RMS},"
        fi
        if [[ "$DATA_KIND" == "VOLTAGE" ]]; then
            PERFDATA="${PERFDATA} circuit_${CIRCUIT}_voltage=${VOLTAGE},"
        fi
        if [[ "$DATA_KIND" == "WATTAGE" ]]; then
            PERFDATA="${PERFDATA} circuit_${CIRCUIT}_wattage=${POWER},"
        fi
        # if [[ "$DATA_KIND" == "VOLTAGE" ]]; then
        #     PERFDATA="${PERFDATA} circuit_${CIRCUIT}_volt_amperes=${VA},"
        # fi
    fi
done <<< "$DATA"

# Trim leading space from PERFDATA
PERFDATA=$(echo "$PERFDATA" | sed 's/^[[:space:]]*//')

# Output Nagios format
echo "OK - $PDU_NAME | $PERFDATA"
exit 0
