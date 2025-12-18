#!/usr/bin/env python3
"""Parse BayTech MMP-14DE PDU data and output Nagios performance data.

Usage: ./parse_pdu.py <data_file> <PDU-NAME> [AMPS|KWH|TEMP|VOLTAGE|WATTAGE]
"""

import os
import re
import sys
import time

MAX_AGE = 900  # 15 minutes in seconds


def main():
    if len(sys.argv) < 3:
        print("FAILED - Usage: parse_pdu.py <data_file> <PDU-NAME> [AMPS|KWH|TEMP|VOLTAGE|WATTAGE]")
        sys.exit(3)

    data_file_base = sys.argv[1]
    pdu_name = sys.argv[2]
    data_kind = sys.argv[3] if len(sys.argv) > 3 else "AMPS"

    if not pdu_name:
        print("FAILED - PDU name is required")
        sys.exit(3)

    data_file = f"{data_file_base}.{pdu_name}"

    if data_file != "/dev/stdin" and not os.access(data_file, os.R_OK):
        print(f"FAILED - Cannot read file: {data_file}")
        sys.exit(3)

    # Check file age
    file_age = int(time.time() - os.stat(data_file).st_mtime)
    if file_age >= MAX_AGE:
        print(f"FAILED - File is stale ({file_age} seconds old)")
        sys.exit(3)

    # Read file content
    with open(data_file, "r") as f:
        data = f.read()

    perfdata = []
    overall_status = []

    # Extract Total kW-h
    if data_kind == "KWH":
        match = re.search(r"^Total kW-h:\s*(\S+)", data, re.MULTILINE)
        if match:
            kwh = match.group(1).strip()
            overall_status.append(f"Total kW-h: {kwh}")
            perfdata.append(f"total_kwh={kwh};;")

    # Extract Internal Temperature
    if data_kind == "TEMP":
        match = re.search(r"^Int\. Temp:\s+(\S+)", data, re.MULTILINE)
        if match:
            temp_f = float(match.group(1))
            celsius = round((temp_f - 32) * 5 / 9, 1)
            overall_status.append(f"Internal Temperature: {celsius} C")
            perfdata.append(f"internal_temp_celsius={celsius};;")

    # Extract Circuit Breaker data (Input A, CKT1, CKT2)
    breaker_pattern = re.compile(
        r"\|\s*([^|]+)\s*\|\s*([0-9.]+)\s*Amps\s*\|\s*([0-9.]+)\s*Amps\s*\|"
    )

    total_amps_peak = 0.0
    total_amps_value = 0.0

    for match in breaker_pattern.finditer(data):
        name = match.group(1).strip().replace(" ", "_").lower()
        true_rms = match.group(2)
        peak_rms = match.group(3)

        if re.match(r"^(input_a|ckt[0-9]+)$", name) and data_kind == "AMPS":

            if name != "input_a":
                total_amps_peak += float(peak_rms)
                total_amps_value += float(true_rms)

            perfdata.append(f"{name}_true_rms_current={true_rms};;")
            perfdata.append(f"{name}_peak_rms_current={peak_rms};;")
   
    perfdata.append(f"cal_total_true_rms_current={total_amps_peak};;")
    perfdata.append(f"cal_total_peak_rms_current={total_amps_value};;")
    
    # Extract Circuit Group data (M1-M4) with voltage, power, VA
    circuit_pattern = re.compile(
        r"\|\s*Circuit\s+(M[0-9]+)\s*\|\s*([0-9.]+)\s*Amps\s*\|\s*([0-9.]+)\s*Amps\s*\|"
        r"\s*([0-9.]+)\s*Volts\s*\|\s*([0-9]+)\s*Watts\s*\|\s*([0-9]+)\s*VA\s*\|"
    )

    for match in circuit_pattern.finditer(data):
        circuit = match.group(1).lower()
        true_rms = match.group(2)
        peak_rms = match.group(3)
        voltage = match.group(4)
        power = match.group(5)
        # va = match.group(6)  # Not used currently
        if data_kind == "AMPS":
            perfdata.append(f"circuit_{circuit}_true_rms_current={true_rms};;")
            perfdata.append(f"circuit_{circuit}_peak_rms_current={peak_rms};;")
        if data_kind == "VOLTAGE":
            overall_status.append(f"{circuit}: {voltage} Volt")
            perfdata.append(f"circuit_{circuit}_voltage={voltage};;")
        if data_kind == "WATTAGE":
            overall_status.append(f"{circuit}: {power} Watt")
            perfdata.append(f"circuit_{circuit}_wattage={power};;")

    if data_kind == "AMPS":
        overall_status.append(f"Total Amps Peak: {total_amps_peak}, Total Amps Value: {total_amps_value}")

    # Output Nagios format
    perfdata_str = " ".join(perfdata)
    overall_status_str = " ".join(overall_status)
    
    print(f"OK - {pdu_name} {overall_status_str} | {perfdata_str}")
    sys.exit(0)

if __name__ == "__main__":
    main()
