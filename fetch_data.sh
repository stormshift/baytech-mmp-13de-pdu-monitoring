#!/bin/bash
set -euo pipefail

# Fetch BayTech MMP-14DE PDU data via avocent
# Usage: ./fetch_data.sh <PDU-NAME> <fileprefix>

PDU_NAME="${1}"
FILE_PREFIX="${2}"

if [[ -z "$PDU_NAME" ]]; then
    echo "UNKNOWN - PDU name is required"
    exit 3
fi

TMP_FILE=$(mktemp)
trap "rm -f $TMP_FILE" EXIT

ssh -tt -q -i ~/.ssh/coe-muc-rsa \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    admin:${PDU_NAME}@avocent.coe.muc.redhat.com 'Status' 2>&1 >$TMP_FILE &

SSH_PID=$!
trap "kill $SSH_PID 2>/dev/null" EXIT

while true; do 
    sleep 10
    strings $TMP_FILE | grep -qm1 'Type Help for a list of commands' && break
done

kill $SSH_PID 2>/dev/null

cp $TMP_FILE $FILE_PREFIX.${PDU_NAME}

echo "OK - Data fetched from $PDU_NAME";
exit 0;
