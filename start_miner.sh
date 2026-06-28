#!/bin/bash
# Antminer U3 启动脚本，由 systemd 以 renfei 用户运行。
set -euo pipefail

export https_proxy=http://10.10.0.133:7890
export http_proxy=http://10.10.0.133:7890
export all_proxy=socks5://10.10.0.133:7890

cd /home/renfei/antminer
exec ./cgminer --config /home/renfei/antminer/miner.conf "$@"

