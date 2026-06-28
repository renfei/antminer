# Antminer U3 日常运维命令与配置位置

记录时间：2026-06-26  
远端主机：`renfei@10.10.1.109`  
矿机服务：`antminer-u3.service`

## 登录远端

```bash
ssh renfei@10.10.1.109
```

如需 root：

```bash
su -
```

## 常用服务命令

查看服务状态：

```bash
systemctl status antminer-u3.service
```

启动：

```bash
systemctl start antminer-u3.service
```

停止：

```bash
systemctl stop antminer-u3.service
```

重启：

```bash
systemctl restart antminer-u3.service
```

查看是否开机自启：

```bash
systemctl is-enabled antminer-u3.service
```

查看当前是否运行：

```bash
systemctl is-active antminer-u3.service
```

启用开机自启：

```bash
systemctl enable antminer-u3.service
```

禁用开机自启：

```bash
systemctl disable antminer-u3.service
```

## 日志查看

实时日志：

```bash
journalctl -u antminer-u3.service -f
```

最近 100 行日志：

```bash
journalctl -u antminer-u3.service -n 100 --no-pager
```

查看本次启动后的日志：

```bash
journalctl -u antminer-u3.service -b --no-pager
```

## 算力与矿池状态

推荐使用已安装的易读命令：

```bash
u3-status
```

实时刷新：

```bash
u3-status watch
```

每 2 秒刷新：

```bash
u3-status watch 2
```

重点看：

```text
服务设备: AU3
状态: Alive
矿池状态: Alive
当前算力
平均算力
Accepted
Rejected
硬件错误
设备错误率
```

## cgminer 原始 API 命令

查看汇总：

```bash
printf 'summary' | nc -w 3 127.0.0.1 4028
```

查看设备：

```bash
printf 'devs' | nc -w 3 127.0.0.1 4028
```

查看矿池：

```bash
printf 'pools' | nc -w 3 127.0.0.1 4028
```

查看 API 是否可用：

```bash
printf 'version' | nc -w 3 127.0.0.1 4028
```

## 重要文件位置

源码目录：

```bash
/home/renfei/antminer
```

cgminer 可执行文件：

```bash
/home/renfei/antminer/cgminer
```

矿池与 U3 参数配置：

```bash
/home/renfei/antminer/miner.conf
```

启动脚本：

```bash
/home/renfei/antminer/start_miner.sh
```

systemd 服务文件：

```bash
/etc/systemd/system/antminer-u3.service
```

USB 自动绑定脚本：

```bash
/usr/local/sbin/u3-bind-cp210x.sh
```

易读状态查看脚本：

```bash
/usr/local/bin/u3-status
```

## 当前 miner.conf 模板

U3 默认参数建议使用：

```json
{
    "pools": [
        {
            "url": "stratum+tcp://pool.btc-classic.org:63201",
            "user": "cc1qnq533qzl52ut9w6vezzf2xqu4zz7zx00000000.u3",
            "pass": "x"
        }
    ],
    "au3-freq": "225",
    "au3-volt": "750",
    "api-listen": true,
    "api-port": "4028",
    "hotplug": "5",
    "no-submit-stale": true
}
```

说明：

- `au3-freq=225` 是 cgminer 里 U3 的默认频率。
- `au3-volt=750` 是 cgminer 里 U3 的默认电压。
- 如果要保守运行，可以用 `au3-freq=200`。
- 如果追求接近 63G，可以尝试 `au3-freq=250`，但要观察硬件错误率和供电散热。

改完配置后重启：

```bash
systemctl restart antminer-u3.service
u3-status watch
```

## 编译命令

如果需要重新编译：

```bash
cd /home/renfei/antminer
make clean
./configure --enable-icarus CFLAGS='-O2 -fcommon'
make -j$(nproc)
```

验证编译结果：

```bash
grep -E 'USE_ICARUS|USE_BMSC' config.h
./cgminer --help | grep -E 'Built with|au3'
```

期望：

```text
/* #undef USE_BMSC */
#define USE_ICARUS 1
Built with icarus mining support.
```

## USB 检查与修复

查看 USB 是否识别：

```bash
lsusb
```

期望看到：

```text
ID 10c4:ea60 Silicon Labs CP210x UART Bridge
```

查看串口设备：

```bash
ls -l /dev/ttyUSB* /dev/serial/by-id/* 2>/dev/null
```

手动执行 USB 绑定脚本：

```bash
/usr/local/sbin/u3-bind-cp210x.sh
```

手动绑定 CP210x：

```bash
echo 2-1:1.0 > /sys/bus/usb/drivers/cp210x/bind
```

## 手动运行 cgminer

一般不建议手动运行，优先用 systemd。若临时手动运行，先停止服务，避免两个 cgminer 抢同一个 U3：

```bash
systemctl stop antminer-u3.service
cd /home/renfei/antminer
nohup ./cgminer --config /home/renfei/antminer/miner.conf --text-only > cgminer.log 2>&1 &
```

查看手动日志：

```bash
tail -f /home/renfei/antminer/cgminer.log
```

停止手动进程：

```bash
pkill cgminer
```

恢复 systemd：

```bash
systemctl start antminer-u3.service
```

## 快速判断问题

矿池正常：

```text
矿池状态: Alive
Stratum: true
```

设备正常：

```text
服务设备: AU3
状态: Alive
```

不正常情况：

```text
No ASCs
```

通常表示 cgminer 没识别到 U3，优先检查：

1. 是否编译了 `--enable-icarus`
2. `/dev/ttyUSB0` 是否存在
3. 是否有其他 cgminer 进程占用设备
4. USB 线、供电、矿机是否稳定

硬件错误高：

```text
Hardware Errors
Device Hardware%
```

优先处理：

1. 降低 `au3-freq`
2. 检查电源
3. 加强散热
4. 更换 USB 线
