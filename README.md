# bbrx — 面向"高 RTT + 中高丢包"链路的 BBR 改进版

`bbrx` 是一个可加载的 TCP 拥塞控制模块（out-of-tree，GPL-2.0），在 **BBR v1** 之上做了**一处**针对性改动，
解决一个在跨太平洋链路上反复观测到的现象：

> **约 1/3 的连接在高峰丢包时会"卡死"在 ~1 Mbps 且整段不恢复。**

## 现象与根因

- 现象：`bbr_bw` 冻结在 0.9 ~ 3.9 Mbps（正常流 15 ~ 50 Mbps），cwnd 只有 ~64 包（正常 ~800），
  与 "1 Mbps 流在 BBR 公式下的必然数值" 完全吻合；重传段数只有正常流的 1/10（说明它**根本没把数据发出去**）。
- 根因（用逐秒 `ss` 轨迹判定）：**STARTUP 阶段过早退出**——卡死流在 **1.3 ~ 1.5 秒（约 7 个 RTT）** 就判"管道已满"
  进入 PROBE_BW，之后每个探测周期只增长 **1.2 ~ 2.2%**（`1.25×(1−p)≈1.0` 量级），**再也爬不出来**。

## 改动（相对 BBR v1）

1. **门控内延长 STARTUP**：当带宽估计 `bw < floor_mbps` 且处于前 `floor_rounds` 轮时，**暂不退出 STARTUP**。
2. **门控内降低 STARTUP 增益**：`high_gain 2885→476 (1.86×)`，**只在"增长已停滞（`full_bw_cnt≥1`）且 `bw<floor`"时生效**，
   使快线起步不受影响（这是关键：早期版本在**建连第 0 秒**就降增益，把正常流的启动拖慢了近一半）。
3. 补偿类改动（`1/(1−p)`）**默认关闭**：实测在限速器下会正反馈，收益为负。

所有新增行为都由 `bw < floor_mbps` 这一**绝对下限**门控：
只要线路的"每流正常速率"明显高于该下限，`bbrx` 的行为与原生 BBR **完全一致**，只在真正卡死时才介入。

## 效果（实测）

| 场景 | 基线 bbrplus | **bbrx** |
|---|---|---|
| vps1 峰时（ab_pair 配对 60 对） | 卡死率 **28.3%** | **0.0%**（Fisher 单侧 p=0.0000，McNemar p=0.0000；非卡死流中位比 1.254） |
| vps1 峰时（flowlab，180 流/臂） | 卡死率 **20.1%** | **0.6%**（Fisher p=0.000；轮内配对中位比 1.223，符号检验 p=0.027） |
| vps2（30% 丢包，ab_pair 30 对） | 卡死率 61.5% | **13.3%**（全体均值比 **1.820**） |
| 仿真（20% 丢包，无瓶颈，n≈50/臂） | 卡死率 20% | **0%**（中位 +279 ~ 320%） |

详细数据见 [`docs/EVIDENCE.md`](docs/EVIDENCE.md)，设计说明见 [`docs/DESIGN.md`](docs/DESIGN.md)。

## 兼容性

- 内核：**6.6.x**、**6.12.x**（out-of-tree 模块，需对应内核头文件；**内核升级后必须重编译**）。
  源码使用了 `__bpf_kfunc` 标注（6.4+ 引入），**6.1 等更旧内核无法直接编译**（报 `expected ';' before 'static'`）。
- 与 `bbrplus` 可共存；`bbrx` 作为独立 CC 注册，互不影响。
- 名字统一：CC 名 `bbrx`、模块文件 `tcp_bbrx.ko`。

## 快速开始

```bash
make                                  # 需要内核头文件
sudo insmod ./tcp_bbrx.ko             # 或 make install
sudo sysctl -w net.ipv4.tcp_congestion_control=bbrx
cat /sys/module/tcp_bbrx/parameters/* # 参数
```

持久化与失败安全安装见 [`INSTALL.md`](INSTALL.md)。

## 风险

- `floor_mbps` 必须**明显低于该线路的每流正常速率**；若你的线路每流本身就低于 4 Mbps，请把它调小（1 ~ 2）。
- 门控内仍使用 STARTUP 增益，对**客户端本身是慢线路**的极端场景可能超发（这是 `floor_mbps` 需要按线设置的原因）。
- 授权：GPL-2.0。

## 已知构建陷阱

1. **`CONFIG_DEBUG_INFO_BTF` 关闭时模块加载失败（EINVAL）**：内核 `register_btf_kfunc_id_set()`
   在 set 缺少 `BTF_SET8_KFUNCS` 标志时直接返回 `-EINVAL`，而 BTF 关闭时 `BTF_SET8_START` 生成的 set
   不带该标志，导致模块 init 失败、`insmod` 报 "Invalid argument"。本源码已用
   `#ifdef CONFIG_DEBUG_INFO_BTF` 守卫该注册；自行改动时不要去掉。
2. **6.10+ 的 `cong_control` 是四参数** `(sk, ack, flag, rs)`，本源码用 `LINUX_VERSION_CODE` 版本宏
   同时兼容 6.6 与 6.12。
3. **LKL/用户态内核**：默认 CC 只改 `CONFIG_DEFAULT_TCP_CONG` 无效，还须在 `net/ipv4/Kconfig` 加
   `config DEFAULT_BBRX` 与 `default "bbrx" if DEFAULT_BBRX`，否则被 cubic 覆盖。

## 关于拥塞控制的运行时选择

- 本模块注册名为 **`bbrx`**，与内核自带的 `bbr` 并存；切换用
  `sysctl -w net.ipv4.tcp_congestion_control=bbrx`（只影响新连接）。
- 开机默认：`/etc/modules` 加 `tcp_bbrx` + `/etc/sysctl.d/99-bbrx.conf` 写
  `net.ipv4.tcp_congestion_control=bbrx`（或由 init 脚本在模块加载后设置）。
- **用户态内核（LKL / OpenVZ）**：hijack 的 JSON **支持 `"sysctl"` 字段**，可在调用时指定 CC：
  `"sysctl":"net.ipv4.tcp_congestion_control=bbrx;net.ipv4.tcp_rmem=..."`。

## 适用范围与已知局限

- **效果数据的来源**：卡死率 28.3%→0%、20.1%→0.6% 等峰时数据是在 **6.6 内核的外部模块**上测的；
  6.12 内核内置版只做过**干净窗口无回归**验证（20 对，中位比 1.019；20 对、p≈0.26 **不足以证明等价**，
  只能排除约 5~10% 以上的回归）。6.12 上的峰时收益尚待复测。
- **`floor_mbps` 是线路先验**：默认 4 适用于每流正常速率远高于 4 Mbps 的链路；客户端只有几 Mbps 时
  应降到 1~2，否则门控期间可能超发。
- **用户态内核（LKL/OpenVZ）**：只验证了 CC 名字生效 / 模块加载正常，**未验证**卡死行为
  （LKL 的定时器与 pacing 与真实内核不同）。
- **形态**：6.12 已内置（`CONFIG_TCP_CONG_BBRX=y`）；6.6 上仍是外部模块，**内核升级后需重编**。
- **回退**：`sysctl -w net.ipv4.tcp_congestion_control=bbrplus`（若内核保留 bbrplus）。
