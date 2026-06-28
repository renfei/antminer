# Antminer U3 Debian 11 环境编译与配置记录

记录时间：2026-06-26  
目标设备：Antminer U3  
远端主机：`renfei@10.10.1.109`  
系统：Debian GNU/Linux 11 bullseye, Linux 5.10.0-44-amd64, x86_64

## 结论

Debian 11 可以运行 Antminer U3，不需要退回非常老的系统。

本次真正的问题有两个：

1. 旧 cgminer 代码在 GCC 10+ 上编译会遇到 `multiple definition`，需要加 `-fcommon`。
2. U3 需要 cgminer 的 `icarus` 驱动，原环境只编译了 `bmsc`，导致能看到 USB 设备但不能按 U3 正常挖矿。

最终可用组合：

```bash
./configure --enable-icarus CFLAGS='-O2 -fcommon'
make -j$(nproc)
```

运行验证结果：

```text
service: active
device: AU3
pool: Alive
GHS av: 51.74
GHS 5s: 46.61
Accepted: 351
Rejected: 0
Hardware Errors: 3
```

## 系统与硬件识别

系统信息：

```text
Linux antminer 5.10.0-44-amd64
Debian GNU/Linux 11 (bullseye)
```

USB 识别：

```text
Bus 002 Device 002: ID 10c4:ea60 Silicon Labs CP210x UART Bridge
```

U3 通过 CP2102 USB 串口桥连接。内核模块：

```bash
cp210x
usbserial
```

如果 `lsusb` 能看到 `10c4:ea60`，但没有 `/dev/ttyUSB0`，可以手动绑定：

```bash
echo 2-1:1.0 > /sys/bus/usb/drivers/cp210x/bind
```

本次已写入自动绑定脚本，服务启动前会自动处理。

## 依赖安装

远端没有 `sudo`，使用 `su -` 进入 root。

安装依赖：

```bash
apt-get update
apt-get install -y \
  git build-essential autoconf automake libtool pkg-config \
  libcurl4-openssl-dev libudev-dev libusb-1.0-0-dev \
  libncurses5-dev uthash-dev screen ca-certificates libjansson-dev
```

## cgminer 编译

源码目录：

```bash
/home/renfei/antminer
```

错误编译方式：

```bash
./configure --enable-bmsc
make -j$(nproc)
```

该方式会生成只支持 `bmsc` 的 cgminer：

```text
Built with bmsc mining support.
#define USE_BMSC 1
/* #undef USE_ICARUS */
```

现象：

```text
Pool Status=Alive
devs: No ASCs
```

或者持续 BMSC nonce 自检，但无有效设备和算力。

正确编译方式：

```bash
cd /home/renfei/antminer
make clean
./configure --enable-icarus CFLAGS='-O2 -fcommon'
make -j$(nproc)
```

验证：

```bash
grep -E 'USE_ICARUS|USE_BMSC' config.h
./cgminer --help | grep -E 'Built with|au3'
```

期望输出：

```text
/* #undef USE_BMSC */
#define USE_ICARUS 1
Built with icarus mining support.
--au3-freq <arg>    Set AntminerU3 frequency in MHz, range 100-250
--au3-volt <arg>    Set AntminerU3 voltage in mv, range 725-850
```

### GCC 10+ 兼容问题

如果不加 `-fcommon`，会在链接阶段报大量类似错误：

```text
multiple definition of `icarus_drv'
multiple definition of `selective_yield'
collect2: error: ld returned 1 exit status
```

原因是旧 C 项目依赖 GCC 老版本默认的 common symbol 行为，而 Debian 11 的 GCC 默认改为 `-fno-common`。

解决：

```bash
CFLAGS='-O2 -fcommon'
```

## miner.conf

配置文件：

```bash
/home/renfei/antminer/miner.conf
```

最终内容：

```json
{
    "pools": [
        {
            "url": "stratum+tcp://pool.btc-classic.org:63201",
            "user": "cc1qnq533qzl52ut9w6vezzf2xqu4zz7zx00000000.u3",
            "pass": "x"
        }
    ],
    "au3-freq": "200",
    "au3-volt": "750",
    "api-listen": true,
    "api-port": "4028",
    "hotplug": "5",
    "no-submit-stale": true
}
```

说明：

- `au3-freq=200`：保守频率，先保证稳定。
- `au3-volt=750`：默认安全电压。
- 如果硬件错误长期很低，可以再尝试提高到 `225`。
- 如果硬件错误明显升高，应降低频率或检查供电、散热、USB 线。

## USB 自动绑定脚本

脚本路径：

```bash
/usr/local/sbin/u3-bind-cp210x.sh
```

内容：

```sh
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
```

权限：

```bash
chmod 755 /usr/local/sbin/u3-bind-cp210x.sh
```

## 启动脚本

脚本路径：

```bash
/home/renfei/antminer/start_miner.sh
```

内容：

```bash
#!/bin/bash
# Antminer U3 启动脚本，由 systemd 以 renfei 用户运行。
set -euo pipefail

export https_proxy=http://10.10.0.133:7890
export http_proxy=http://10.10.0.133:7890
export all_proxy=socks5://10.10.0.133:7890

cd /home/renfei/antminer
exec ./cgminer --config /home/renfei/antminer/miner.conf "$@"
```

权限：

```bash
chown renfei:renfei /home/renfei/antminer/start_miner.sh
chmod 755 /home/renfei/antminer/start_miner.sh
```

## systemd 服务

服务文件：

```bash
/etc/systemd/system/antminer-u3.service
```

内容：

```ini
[Unit]
Description=Antminer U3 cgminer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
PermissionsStartOnly=true
User=renfei
Group=dialout
WorkingDirectory=/home/renfei/antminer
ExecStartPre=/usr/local/sbin/u3-bind-cp210x.sh
ExecStart=/home/renfei/antminer/start_miner.sh --text-only
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

关键点：

- `PermissionsStartOnly=true`：确保 `ExecStartPre` 以 root 执行，才能写 `/sys/bus/usb/drivers/cp210x/bind`。
- 主进程仍以 `renfei` 用户运行。
- `Group=dialout`：允许访问 `/dev/ttyUSB0`。

启用：

```bash
systemctl daemon-reload
systemctl enable antminer-u3.service
systemctl restart antminer-u3.service
```

## 验证命令

查看服务：

```bash
systemctl status antminer-u3.service
```

实时日志：

```bash
journalctl -u antminer-u3.service -f
```

查看矿池：

```bash
printf 'pools' | nc -w 3 127.0.0.1 4028
```

查看设备：

```bash
printf 'devs' | nc -w 3 127.0.0.1 4028
```

查看汇总：

```bash
printf 'summary' | nc -w 3 127.0.0.1 4028
```

成功状态示例：

```text
POOL=0,URL=stratum+tcp://pool.btc-classic.org:63201,Status=Alive
ASC=0,Name=AU3,Enabled=Y,Status=Alive
Accepted=351
Rejected=0
Hardware Errors=3
GHS av=51.74
```

## 排障记录

### 能看到 USB，但没有 ttyUSB0

现象：

```bash
lsusb
# Bus 002 Device 002: ID 10c4:ea60 Silicon Labs CP210x UART Bridge

ls /dev/ttyUSB*
# 没有文件
```

处理：

```bash
modprobe cp210x
echo 2-1:1.0 > /sys/bus/usb/drivers/cp210x/bind
```

### Pool Alive，但 devs 返回 No ASCs

原因：

cgminer 编译成了 `bmsc`，没有启用 `icarus`。

处理：

```bash
make clean
./configure --enable-icarus CFLAGS='-O2 -fcommon'
make -j$(nproc)
```

### systemd 前置脚本 Permission denied

现象：

```text
cannot create /sys/bus/usb/drivers/cp210x/bind: Permission denied
```

原因：

`ExecStartPre` 也被 `User=renfei` 限制了。

处理：

```ini
PermissionsStartOnly=true
```

### 尝试 `--usb AU3:1` 失败

现象：

```text
Invalid --usb DRV:limit - unknown DRV='AU3'
```

结论：

`--usb` 不能用 `AU3` 作为 driver 名。回滚该参数后，cgminer 会自动正确识别为 `AU3`。

## 推荐操作系统

推荐：

1. Debian 11 bullseye
2. Debian 10 buster
3. Ubuntu 20.04 LTS

不推荐：

- Debian 12/13、Ubuntu 22.04/24.04：也许能用，但旧 cgminer 兼容成本更高。
- Debian 7/8、Ubuntu 14.04：包源、证书、TLS 和依赖安装会更麻烦。
- 32 位系统：没有必要。

## 后续调优建议

当前配置优先稳定，频率是 `200`。如果运行数小时后：

- `Rejected=0`
- `Hardware Errors` 比例低
- 温度和供电稳定

可以尝试：

```json
"au3-freq": "225",
"au3-volt": "750"
```

如果硬件错误上升，回退到 `200`。U3 对供电和 USB 线比较敏感，算力不稳定时优先检查电源、散热和线材。
