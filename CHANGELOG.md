# CHANGELOG

## v1.0.0 — 首个发布
- 基于 BBR v1，新增"下限门控内延长 STARTUP + 停滞时降低 STARTUP 增益"。
- 修复：`bbrx_high_gain` 默认值曾被位域截断（1500→476），现显式写出并加 `min(...,1023)` 钳位。
- 修复：`bbrx_lt_disable`、`bbrx_rtt_win_sec` 改为 `static const`（原可写会触发已删字段的死代码 / ProbeRTT 反复）。
- 实测：vps1 峰时卡死率 28.3%→0%（ab_pair 60 对，p=0.0000）、20.1%→0.6%（flowlab 180 流/臂，p=0.000）；
  vps2 61.5%→13.3%（全体均值比 1.820）。七组仿真场景零回归。
- 兼容：6.6.x / 6.12.x；与 bbrplus 共存。
