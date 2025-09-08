#!/bin/bash

# A simple system monitoring script

# Colors
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

echo -e "${CYAN}========== System Monitor ==========${RESET}"
echo -e "${YELLOW}Hostname:$(hostname)   Date:$(date)${RESET}"
echo

# CPU Usage
echo -e "${GREEN}--- CPU Usage ---${RESET}"
mpstat 1 1 | awk '/Average:/ {printf "CPU Idle: %.2f%% | CPU Used: %.2f%%\n", $12, 100-$12}'
echo

# Memory Usage
echo -e "${GREEN}--- Memory Usage ---${RESET}"
free -h | awk 'NR==2 {printf "Used: %s | Free: %s | Total: %s\n", $3, $4, $2}'
echo

# Disk Usage
echo -e "${GREEN}--- Disk Usage ---${RESET}"
df -h --total | awk '/total/ {printf "Used: %s | Free: %s | Total: %s\n", $3, $4, $2}'
echo

# Top 5 Memory-Hungry Processes
echo -e "${GREEN}--- Top 5 Memory Processes ---${RESET}"
ps -eo pid,comm,%mem,%cpu --sort=-%mem | head -n 6
echo

# Network Usage (RX/TX bytes)
echo -e "${GREEN}--- Network Usage ---${RESET}"
IFACE=$(ip route | grep '^default' | awk '{print $5}')
if [ -n "$IFACE" ]; then
    RX=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
    TX=$(cat /sys/class/net/$IFACE/statistics/tx_bytes)
    echo "Interface: $IFACE | RX: $((RX/1024/1024)) MB | TX: $((TX/1024/1024)) MB"
else
    echo "No active network interface found."
fi

echo -e "${CYAN}====================================${RESET}"
