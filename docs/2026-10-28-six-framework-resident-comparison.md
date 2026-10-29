# 六框架常驻 quick launcher 公平性能对比

日期：2026-10-28

原始结果：[`results/2026-10-28/2026-10-28-six-framework-resident.json`](../results/2026-10-28/2026-10-28-six-framework-resident.json)

协议与复现：[`README.md`](../README.md)

## 结论

这次测试不是冷启动测试。六个 probe 都作为不会自动退出的后台进程运行，实际覆盖：后台隐藏、warm show、可见后采样、400 次共享状态更新、warm hide、隐藏 15 秒后采样、30 次显隐循环，以及循环后再次隐藏采样。

在这台机器上：

- **gpui-ce 的常驻内存最低，warm show 也处于最快一档。** 隐藏时 Private Working Set（PWS）中位数 23.8 MB，workload 时 37.3 MB。不过它在 3 轮中的 2 轮于 hide 后静置 15 秒仍录得明显 CPU（post-hide 中位数为单核 54.0%、整机 1.688%）；在把它选作后台守护进程框架前，应先定位这个 hidden-state CPU 行为。
- **Slint 是第二轻的常驻方案，隐藏后 CPU/GPU 能回到零。** 隐藏 PWS 33.2 MB，workload PWS 60.7 MB；代价是本机 workload GPU engine 最高（平均 5.378%、峰值 8.988%），warm show 也比 zgui、gpui-ce、Tauri 和 Dioxus Native 慢。
- **zgui 的内存处于 Slint 与 WebView 方案之间，显隐很快，但显存不低。** 隐藏 PWS 87.6 MB，workload PWS 96.5 MB，warm show 中位数 238.7 ms，为六者最快；但 workload dedicated/shared GPU memory 峰值约 144.1/36.3 MB。
- **简化 Tauri probe 明显优于 Dioxus Desktop probe，但两者都有 WebView2 的固定常驻成本。** Tauri workload PWS/整机 CPU 为 107.1 MB/0.328%，Dioxus Desktop 为 132.2 MB/1.639%；Tauri 的 show/hide 也更快。两者隐藏时均为 8 个进程、2 个 renderer。
- **Tauri 的 GPU memory 确实低于 zgui。** workload 峰值 Tauri 为 dedicated 108.6 MB + shared 2.2 MB，zgui 为 144.1 MB + 36.3 MB。Tauri 的 GPU engine 利用率在该 workload 中接近计数器下限，而 zgui 平均为 0.413%。
- **Dioxus Native/Blitz 在当前 pin 下不是轻量常驻方案。** 隐藏 PWS 190.5 MB、Private Bytes 315.6 MB，workload GPU memory 峰值约 154.2/74.2 MB；它的 workload CPU 却很低（整机 0.327%），warm show 也不差。当前组合使用 Dioxus 0.8 alpha、Blitz beta，且多窗口显隐仍需要很薄的 Win32 adapter，应把成熟度和集成成本一并考虑。

如果只看当前数据，**gpui-ce 在 footprint 上领先，Slint 是更稳妥的低内存/隐藏零 CPU 候选，Tauri 则在中等内存成本下给出很低的 workload CPU/GPU 和成熟的桌面能力**。gpui-ce 的 hide 后 CPU 异常、以及 Slint 的 workload GPU 成本，是下一轮决策前最值得追加 profiler 实验的两点。

## 公平实验设计

每套 probe 都实现同一最小业务规模：

- 两个窗口，内容尺寸分别为 700×480 与 1200×760；
- 主窗口 72 个 shortcut rows；辅助窗口 66-key atlas、preview、navigation、numpad 和 dossier；
- 一个业务 controller，同时驱动两个窗口的 selection；
- workload 固定为 400 次更新，每次间隔 20 ms，总计 8 秒；
- release + lockfile 构建，3 轮，框架顺序按轮次旋转；
- Windows 进程树整体采样，不只看主进程；
- show/hide latency 从命令发送计时，直到 harness 确认两个 HWND 都达到目标状态。

测试机器为 Windows 11 build 26200、Ryzen 9 7945HX、32 logical processors，显示适配器包含 RTX 4060 Laptop GPU 与 Radeon Graphics。GPU 计数器按进程树和所有匹配 engine/adapter 汇总，所以适合在同一机器内横向比较，不应直接与另一台机器的绝对值混用。

生产 Tauri 应用没有参加排名；参赛的是缩减后的 `tauri-probe`，其业务状态、窗口数、列表/atlas 规模、更新次数与其他五者一致，不包含当前产品复杂 UI 和功能机制。

## 结果

除 latency 表明确给出范围外，以下均为 3 轮中位数。完整 min/max、每秒 GPU 样本、显存 start/end/peak、每轮进程清单和窗口拓扑都在原始 JSON 中。

### Artifact 与进程拓扑

| Framework | EXE MB | 隐藏进程数 | Renderer 数 |
|---|---:|---:|---:|
| Tauri | 8.4 | 8 | 2 |
| Slint | 9.8 | 1 | 0 |
| zgui | 28.4 | 1 | 0 |
| Dioxus Desktop | 5.0 | 8 | 2 |
| Dioxus Native/Blitz | 22.2 | 1 | 0 |
| gpui-ce | 22.8 | 1 | 0 |

EXE size 不包含系统 WebView2 runtime，因此不能单独代表部署体积或运行时成本。

### 后台隐藏 idle

| Framework | PWS MB | Private Bytes MB | 整机 CPU % | GPU avg % | Dedicated peak MB | Shared peak MB |
|---|---:|---:|---:|---:|---:|---:|
| Tauri | 100.2 | 246.3 | 0 | 0 | 93.5 | 2.4 |
| Slint | 33.2 | 100.8 | 0 | 0 | 45.7 | 4.2 |
| zgui | 87.6 | 223.3 | 0 | 0 | 146.3 | 32.5 |
| Dioxus Desktop | 100.9 | 255.1 | 0 | 0 | 100.7 | 2.3 |
| Dioxus Native/Blitz | 190.5 | 315.6 | 0 | 0 | 119.5 | 74.2 |
| gpui-ce | 23.8 | 69.5 | 0 | 0 | 7.8 | 0.7 |

六者初始隐藏 idle 的 CPU 中位数均为零。gpui-ce 与 Slint 的内存优势明显；Tauri 和 Dioxus Desktop 的结果很接近，符合共享 WebView2 架构的预期。

### 400×20 ms 共享状态 workload

| Framework | PWS MB | Private Bytes MB | 单核 CPU % | 整机 CPU % | GPU avg / peak % | Dedicated / shared peak MB |
|---|---:|---:|---:|---:|---:|---:|
| Tauri | 107.1 | 262.5 | 10.506 | 0.328 | 0 / 0 | 108.6 / 2.2 |
| Slint | 60.7 | 143.6 | 31.449 | 0.983 | 5.378 / 8.988 | 75.3 / 23.2 |
| zgui | 96.5 | 232.3 | 20.946 | 0.655 | 0.413 / 0.573 | 144.1 / 36.3 |
| Dioxus Desktop | 132.2 | 278.9 | 52.436 | 1.639 | 0.218 / 0.282 | 90.8 / 3.3 |
| Dioxus Native/Blitz | 190.5 | 333.4 | 10.459 | 0.327 | 0 / 0 | 154.2 / 74.2 |
| gpui-ce | 37.3 | 92.1 | 20.805 | 0.650 | 1.826 / 1.921 | 59.5 / 2.1 |

“GPU 为 0”表示 Windows per-process counter 在采样粒度下没有录得可见 activity，不等于框架完全不使用 GPU。显存仍能反映已分配/保留的 GPU resource。

### Warm show / hide latency

| Framework | Show median ms (min–max) | Hide median ms (min–max) |
|---|---:|---:|
| Tauri | 283.704 (279.736–292.659) | **229.853** (220.582–240.067) |
| Slint | 353.855 (319.046–438.483) | 288.170 (267.827–293.006) |
| zgui | **238.664** (230.551–272.711) | 253.169 (237.455–259.736) |
| Dioxus Desktop | 446.801 (412.780–450.307) | 319.299 (299.236–364.454) |
| Dioxus Native/Blitz | 267.202 (243.009–317.973) | 261.848 (242.392–302.708) |
| gpui-ce | 240.554 (238.776–261.492) | 253.732 (226.704–284.958) |

这个 latency 是端到端的“双窗口已达到可见/隐藏状态”时间，不是单次 API 调用耗时；包括控制消息、框架 event loop、OS transition 和 5 ms polling 粒度。zgui 与 Dioxus Native 因当前公开 API 限制使用了 Win32 `ShowWindow` adapter，其 latency 与完全走框架 API 的四者应视为实际集成路径对比，而非纯 API microbenchmark。

### Hide 与重复显隐后的稳态

| Framework | Post-hide PWS MB | Post-hide 整机 CPU % | Post-30-cycle PWS MB | Post-30-cycle 整机 CPU % |
|---|---:|---:|---:|---:|
| Tauri | 104.9 | 0 | 104.2 | 0.558 |
| Slint | 59.8 | 0 | 60.4 | 0 |
| zgui | 96.3 | 0 | 96.3 | 0 |
| Dioxus Desktop | 129.2 | 0 | 124.4 | 0 |
| Dioxus Native/Blitz | 190.3 | 0 | 190.3 | 0 |
| gpui-ce | 35.6 | 1.688 | 35.6 | 0 |

Slint、zgui、Dioxus Desktop 和 Dioxus Native 在两个隐藏检查点的 CPU 中位数均回到零。Tauri 在 30 次循环后的采样仍有少量 WebView CPU。gpui-ce 的 post-hide CPU 中位数来自三轮中的两轮（整机 1.688% 与 1.971%，另一轮为 0），但 30 次循环后又回到零；这更像某个 hide 后仍在运行的任务/重绘周期，而不是单纯测量噪声，值得用 ETW/WPA 或 profiler 继续定位。

## 版本与实现限制

- Tauri 2.12.5，`tauri-build` 2.7.4。
- Slint 1.16.1；这是仓库内自包含 probe，没有修改长期未更新的同级旧项目。
- zgui pinned commit `951a0ea3b113247da6dff439fccbd9097aa3187f`。
- Dioxus Desktop 0.7.10。
- Dioxus Native/Blitz pinned commit `fe33b778baaef5375d941c8a4f491f62cbd31d30`，配套 Dioxus 0.8.0-alpha.3。
- gpui-ce pinned commit `5cac1478fea0a5f6f28ae4bc7df4b552dff8854b`（该 pin 的 crate version 为 0.2.2）。

Dioxus Native 的低层 multi-window 构造目前需要分别维护两个 VDOM；probe 使用一个 `watch` sender 把同一 selection 广播给两个 VDOM。zgui 的 UI event loop 在窗口隐藏时不适合作为 benchmark 命令时钟，因此 workload 的精确 20 ms deadline 在独立控制线程上，UI 仍通过框架 signal 消费全部 400 次状态变化。

## 数据审计与重试

正式主实验产生过两个不能用于结论的 attempt，均保留在仓库：

1. zgui 第 3 轮在初始隐藏拓扑确认失败。审计发现 probe 改造时未长期持有两个 `WindowHandle`，这是隐藏 auxiliary window 偶发释放的最可能原因。修复 handle lifetime 后，release smoke 和正式第 3 轮补测通过。
2. Slint 第 2 轮本身成功，但采样器遇到 Windows PID reuse：一个早已存在的 `node.exe/codex.exe` 的静态 ParentProcessId 恰好等于新的 Slint PID，旧算法把它误收进进程树。采样器现要求 child creation time 不早于 parent，并新增 PID-reuse 单元测试；补测的 Slint 进程树严格为一个 probe 进程。

最终 JSON 有 18 个有效 run，每个 framework/phase 的统计 `count=3`。它还包含 `failedAttempts`、`supersededSuccessfulPairs` 和 assembly 来源；未合并的主 attempts、zgui retry、Slint retry 也分别保留，便于复核而不是静默覆盖异常。

## 建议的下一步

1. 对 gpui-ce 做 hidden-state CPU profile，确认是 probe 调度、框架 timer、渲染循环还是 Windows compositor interaction。
2. 对 Slint workload 做 GPU frame/engine profile，检查 20 ms selection 更新是否触发了超出必要区域的重绘。
3. 如果进入产品原型阶段，在 gpui-ce、Slint、Tauri 三者上再实现一个更接近真实交互的子集：快捷键唤起、搜索过滤、键盘 selection、auxiliary 内容同步与 tray/IPC；仍保持相同数据和脚本。
4. 冷启动可以继续作为补充维度，但不应与这份常驻 show/hide 结果混合排序。
