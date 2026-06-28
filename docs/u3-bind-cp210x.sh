#!/bin/sh
# 绑定 Antminer U3 的 CP210x USB 串口，并等待 /dev/ttyUSB0 出现。
set -eu
modprobe cp210x 2>/dev/null || true
for n in $(seq 1 20); do
  if [ -e /dev/ttyUSB0 ]; then
    chgrp dialout /dev/ttyUSB0 2>/dev/null || true
    chmod 660 /dev/ttyUSB0 2>/dev/null || true
    exit 0
  fi
  for iface in /sys/bus/usb/devices/*:1.0; do
    [ -f "$iface/../idVendor" ] || continue
    vendor=$(cat "$iface/../idVendor")
    product=$(cat "$iface/../idProduct")
    if [ "$vendor:$product" = "10c4:ea60" ]; then
      name=$(basename "$iface")
      if [ ! -L "/sys/bus/usb/drivers/cp210x/$name" ]; then
        echo "$name" > /sys/bus/usb/drivers/cp210x/bind 2>/dev/null || true
      fi
    fi
  done
  sleep 1
done
[ -e /dev/ttyUSB0 ]

