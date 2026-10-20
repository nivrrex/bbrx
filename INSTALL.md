# 安装

## 依赖
- 内核头文件：`apt install linux-headers-$(uname -r) build-essential`
- 目标内核：**6.6.x / 6.12.x**（**内核升级后必须重编译**）
- 更旧内核（如 6.1）会因 `__bpf_kfunc` 未定义而编译失败，这是预期行为。

## 构建
```bash
make                 # 产出 tcp_bbrx.ko
sudo make install    # 可选：装到 /lib/modules/$(uname -r)/extra/
```

## 加载与切换
```bash
sudo insmod ./tcp_bbrx.ko
cat /sys/module/tcp_bbrx/parameters/*      # 确认参数
sudo sysctl -w net.ipv4.tcp_congestion_control=bbrx
```
验证：`sysctl net.ipv4.tcp_congestion_control` 应为 `bbrx`；
`dmesg | grep bbrx` 应看到 `sizeof(struct bbr)=.. priv=..`。

## 持久化（失败安全写法，推荐）

**关键**：`sysctl` 必须在 `insmod` **成功之后**才执行 —— 否则内核升级后模块加载失败，
机器会停在一个不存在的 CC 上。把下面一行加进 `/etc/rc.local` 的 `exit 0` **之前**：

```sh
insmod /opt/bbrx/tcp_bbrx.ko 2>/dev/null && sysctl -qw net.ipv4.tcp_congestion_control=bbrx || true
```

（若发行版用 systemd，等价地写一个 oneshot unit，`ExecStart=` 上面这行。）

## 回滚
```bash
sudo sysctl -w net.ipv4.tcp_congestion_control=bbrplus   # 只影响新连接
# 彻底移除：删掉 rc.local 里那一行 + rm /opt/bbrx/tcp_bbrx.ko
```

## 调参（按线设置）
- **先量**这条线的"每流正常速率"（例如峰时单流中位）。
- `floor_mbps` 取**明显低于**它的值（如 1/10）。默认 4 Mbps 适用于"每流正常速率 ≥ ~15 Mbps"的线。
- 若你的线路每流本身就低于 4 Mbps，把它调到 1 ~ 2，否则门控会一直开着。
