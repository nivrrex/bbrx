# 设计说明

## 1. 只改一处：STARTUP 的"到顶"判定

BBR v1 用 `bbr_check_full_bw_reached()` 判定 STARTUP 是否结束：带宽估计连续 `full_bw_cnt`(3) 轮
未增长超过 `bbr_full_bw_thresh`(1.25×) 就认为"管道已满"。**该判据完全不看丢包**——
在 14~18% 丢包下，送达速率增长被压低，于是一些连接在 **1.3~1.5 秒**就误判到顶。

`bbrx` 增加两条**只在下限门控内生效**的行为：

```c
/* 1) 门控内暂不退出 STARTUP（等价于把 full_bw_cnt 需求放大到"永不满足"） */
if (bbrx_floor_mbps > 0 && bbr_max_bw(sk) < bbrx_floor_bw(sk) &&
    bbr->rtt_cnt < (u32)bbrx_floor_rounds)
        _cnt = (u32)bbrx_fbw_cnt;          /* 门控内用大 cnt */

/* 2) 门控内且"增长已停滞"时才降 STARTUP 增益 */
if (bbrx_floor_mbps > 0 && bbr->full_bw_cnt >= 1 &&
    bbr_max_bw(sk) < bbrx_floor_bw(sk))
        return min_t(int, bbrx_high_gain, 1023);   /* 476 = 1.86x */
```

**为什么第 2 条一定要加 `full_bw_cnt >= 1`**：早期版本没有这个条件，于是**从建连第 0 秒**（`bw=0 < floor`）
就降增益，把正常流的启动拖慢（实测 `bw@10s`：47 vs 93 Mbps，腰斩）。加上"增长已停滞"后，
快线每轮都在增长（`full_bw_cnt` 恒为 0）⇒ 完全不受影响；只有真正停滞的连接才进入门控内。
仿真验证：0% 丢包档从 −8% 回到 **+0%**（first10 恢复 114.29），而 20% 丢包档卡死率仍是 **0%**。

## 2. 为什么用"绝对下限"而不是"丢包率"

尝试过用丢包率门控（只在丢包高时延长 STARTUP）——**失败**：限速器把超额流量丢掉，
在发送端看起来与线路丢包**完全一样**（100M 限速器 + 零丢包场景下重传也能到 37%），
`loss_ema` 分不开两者，结果在限速器下持续超发（−17%）。
改用"带宽量级"就没有这个问题：卡死区在 **1~2 Mbps**，限速器区在 **55~67 Mbps**，量级差 30 倍。

## 3. 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `bbrx_floor_mbps` | 4 | 下限（Mbit/s）。**必须明显低于该线路的每流正常速率**；0=关闭全部新增行为 |
| `bbrx_floor_rounds` | 40 | 下限门控最多作用多少轮（207 ms RTT 下约 8 s） |
| `bbrx_fbw_cnt` | 6 | 门控内的"到顶"轮数阈值。注意 `full_bw_cnt` 是 **2 位位域（≤3）**，故 6 ⇒ **门控内不退出 STARTUP** |
| `bbrx_high_gain` | 476 | 门控内 STARTUP 增益（10 位位域 ≤1023；476 = 1.86×，旧写成 1500 会被**截断**成 476） |
| `bbrx_enable` | 0 | 补偿类改动（`1/(1−p)`）总开关，**默认关**（实测在限速器下正反馈） |

## 4. 已知边界

- 高 RTT 才有意义：`floor_rounds` 以"轮"为单位，30 ms RTT 下 40 轮只有约 1.2 s，需要按 RTT 调整。
- 门控内仍用 STARTUP 增益；客户端本身是慢线路时可能超发。
- `struct bbr` 受 `ICSK_CA_PRIV_SIZE` 限制（实测 6.1 内核 104B、6.6-bbrplus 内核 112B），
  新增字段复用了已禁用的 LT 字段。
