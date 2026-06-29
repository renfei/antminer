#!/usr/bin/env bash

API_HOST="127.0.0.1"
API_PORT="4028"
SERVICE="antminer-u3.service"

MAX_SHARE_IDLE=600
MAX_WORK_IDLE=300

api_call() {
    printf "%s" "$1" | nc -w 3 "$API_HOST" "$API_PORT" 2>/dev/null | tr -d '\0'
}

restart_miner() {
    echo "$(date '+%F %T') $1, restarting $SERVICE"
    systemctl restart "$SERVICE"
}

summary=$(api_call "summary")

if [ -z "$summary" ]; then
    restart_miner "cgminer API no response"
    exit 0
fi

devs=$(api_call "devs")
pools=$(api_call "pools")
now=$(date +%s)

ghs_5s=$(echo "$summary" | tr '|' '\n' | sed -n 's/.*GHS 5s=\([0-9.][0-9.]*\).*/\1/p' | head -n1)
mhs_5s=$(echo "$devs" | tr '|' '\n' | sed -n 's/.*MHS 5s=\([0-9.][0-9.]*\).*/\1/p' | head -n1)

last_share=$(echo "$devs" \
    | tr '|' '\n' \
    | sed -n 's/.*Last Share Time=\([0-9][0-9][0-9][0-9][0-9][0-9]*\).*/\1/p' \
    | head -n1)

last_valid_work=$(echo "$devs" \
    | tr '|' '\n' \
    | sed -n 's/.*Last Valid Work=\([0-9][0-9][0-9][0-9][0-9][0-9]*\).*/\1/p' \
    | head -n1)

pool_status=$(echo "$pools" | tr '|' '\n' | sed -n 's/.*Status=\([^,]*\).*/\1/p' | head -n1)
device_status=$(echo "$devs" | tr '|' '\n' | sed -n 's/.*Status=\([^,]*\).*/\1/p' | head -n1)

hash_ok=0

if [ -n "$ghs_5s" ] && awk "BEGIN {exit !($ghs_5s > 0)}"; then
    hash_ok=1
fi

if [ -n "$mhs_5s" ] && awk "BEGIN {exit !($mhs_5s > 0)}"; then
    hash_ok=1
fi

if [ "$device_status" != "Alive" ]; then
    restart_miner "device status is ${device_status:-N/A}"
    exit 0
fi

if [ "$pool_status" != "Alive" ]; then
    restart_miner "pool status is ${pool_status:-N/A}"
    exit 0
fi

if [ "$hash_ok" != "1" ]; then
    restart_miner "hashrate is zero or missing"
    exit 0
fi

if [ -n "$last_share" ]; then
    share_idle=$((now - last_share))
    if [ "$share_idle" -gt "$MAX_SHARE_IDLE" ]; then
        restart_miner "no share for ${share_idle}s"
        exit 0
    fi
else
    restart_miner "missing last share time"
    exit 0
fi

if [ -n "$last_valid_work" ]; then
    work_idle=$((now - last_valid_work))
    if [ "$work_idle" -gt "$MAX_WORK_IDLE" ]; then
        restart_miner "no valid work for ${work_idle}s"
        exit 0
    fi
else
    restart_miner "missing last valid work"
    exit 0
fi

echo "$(date '+%F %T') ok, device=$device_status, pool=$pool_status, ghs=${ghs_5s:-N/A}, mhs=${mhs_5s:-N/A}, share_idle=${share_idle}s, work_idle=${work_idle}s"

