# 协议审查后的优化与验收

日期：2026-11-01（UTC+8）。用户在[审查报告](protocol-audit-20261101.md)后要求全部优化。本记录是后续实际结果；审查报告中的旧版本、未修复内核和未测 UDP 状态属于变更前快照。

## 已部署

| 对象 | 变更 | 最终验证 |
|---|---|---|
| 诺亚 server1 | 26.10.29 → 官方 26.10.31，pinned | 实际运行 a4a3dff，服务 active，doctor 通过 |
| VMISS server2 | 26.10.29 → 官方 26.10.31，pinned | 实际运行 a4a3dff；Direct 走本机，Relay 仍走诺亚；doctor 通过 |
| 云途 server3_yuntu | 官方安全内核 6.1.158-1 → 6.1.190-1，并完成整机重启 | 运行 6.1.0-54-amd64，SSH/Xray 自动恢复，实际核心仍为 26.10.31，doctor 通过 |
| VMISS server2 | cubic → BBR，持久化模块与 sysctl | 当前 bbr；既有默认 qdisc fq_codel 保留；外部 HTTPS/出口/UDP 验证通过 |

核心升级使用各服务器已有的管理器事务流程，依次先升级诺亚，再升级 VMISS；没有为换核替换管理脚本。候选摘要、私网防护、旧客户端与下游协议预检、正式链路复测均未跳过。

三台分别比较了去掉 core 字段后的完整状态摘要，以及实际 config.json SHA256，全部与变更前一致。身份、Encryption、UUID、REALITY 密钥、SNI、路径和路由保持一致，因此已有分享链接继续有效。诺亚/VMISS 的旧核心归档保留，云途的旧启动内核保留。

节点私密备份位于各服务器 root 专用的 /root/sfxh-opt-20261101/；独立 Windows 测试配置和原始结果位于仅当前用户/SYSTEM 可访问的 .cache/optimization-20261101/，不进入发行包。

## 内核安全与下载

[Debian CVE 跟踪](https://security-tracker.debian.org/tracker/CVE-2026-98432)列出的 bookworm 修复包为 6.1.190-1；[官方 Xray 发行说明](https://github.com/XTLS/Xray-core/releases/tag/v26.10.31)说明 26.10.31 默认关闭 MPTCP。此次同时完成云途内核修复与两台旧核心升级，未将关闭 MPTCP 当成内核修复的替代。

云途 apt 已确认安全源候选版本，但 70.5 MB 包传输缓慢。使用独立 Windows 从同一 Debian 官方 HTTPS 路径下载，按服务器通过 apt 获取的包元数据核对大小与 SHA256，再通过 SSH 传入；仅在确认没有 dpkg 正在运行时中断旧下载。将已校验包放入 apt 缓存，最终仍由 apt 完成安装和引导配置。

包大小 70,491,372 字节，SHA256：d788f148714b4cec6a9ff5e66282f56d9a7a0c2c12ac3e5093de12abaf47f56e。安装后确认 initramfs/内核文件、GRUB 语法、自启状态及 dpkg 完整性，才执行重启。未升级其他 85 个可更新包。

## 性能选择

独立 Windows 客户端通过真实 VMISS→诺亚链式路径下载 Cloudflare 测速数据；各样本 8 MiB，校验 HTTP200 和完整字节数。采用 cubic → BBR → XMUX 对照 → cubic → BBR 的顺序，cubic 与 BBR 各两轮，每轮三次。

| 组合 | 下载样本数 | 短样本吞吐中位数 |
|---|---:|---:|
| cubic，默认 XMUX | 6 | 34.099 Mbps |
| BBR，默认 XMUX | 6 | 77.766 Mbps |
| BBR，客户端 maxConcurrency=1 | 3 | 38.760 Mbps |

共传输 120 MiB 下载应用载荷，不含协议和链式重复计费开销。每个组合同时通过出口和 HTTPS 检查。本轮 BBR 样本整体更好，因此保留并持久化；XMUX=1 没有显示稳定优势，因此未部署。短样本含建连、预热与远端波动，不作为持续吞吐上限，也不宣称固定倍数提速。没有在测试期间改动 qdisc 或重启 VMISS 服务。

VMISS 新增 /etc/sysctl.d/99-sfxh-bbr-20261101.conf 和 /etc/modules-load.d/sfxh-bbr-20261101.conf，原 sysctl 已备份。该节点未为验证持久化额外重启；运行值已确认，配置与模块加载文件已写入。

## 目标与协议参数的最终处理

三台分别实测四个候选的带 SNI TLS 握手：当前 archive.archlinux.org 为 X25519、证书链 3399 字节；Amazon 为 X25519MLKEM768、4287–4351 字节；Yahoo 为 X25519MLKEM768、4572 字节；Cloudflare 为 X25519MLKEM768、2492 字节。新候选本次 TLS ping 总耗时较低，但这不是实际代理请求延迟对比，也不证明网络邻近性最佳。

现有生产节点继续使用 archive.archlinux.org；更换 target/SNI 会涉及已导入客户端与入口保存的下游参数，不能靠单改服务端完成。当前内层 VLESS 已使用 ML-KEM-768，外层后量子目标与 ML-DSA 不是可以直接无损追加的通用调优项。未因追求参数数量而改变 target、加小时间窗、硬编码回落限速或开启 sniffing。后续更换目标需作为完整连接参数迁移执行，不能把候选 TLS 探测称为已部署的全链路后量子升级。

保留现有 native、600s/0rtt、chrome、Vision、XHTTP auto 和官方默认 XMUX；本次验证支持这些选择。保留系统级 net.mptcp.enabled，未为本服务改动其他程序的全局 MPTCP 能力；三台 Xray 均已运行默认关闭 MPTCP 的新核心。

## 源码与持续验证

- .github/workflows/check.yml：核心矩阵保留最低兼容版本 26.9.9，增加 26.10.31；两者均固定官方 Linux ZIP SHA256。矩阵中增加真实协议实验，不只校验 JSON 或模拟网络。
- tests/protocol_lab.py：从 26 项扩展为 36 项。两种 RTT 下新增单跳 UDP、Direct/Relay 双跳 UDP、私网 UDP 阻断及阻断后的正常 UDP。
- UDP 接收器回传实际源地址，实验据此区分入口和出口，防止“UDP 能通但走错出口”被误判为通过。负向用例要求目标接收器实际存在、核心日志明确报告阻断，并以阻断前后的正常传输作对照；不以超时单独证明防护。
- 实验只精确放行测试接收器的 IP/端口和传输类型，不修改生产模板，也不放行整个回环/私网范围。结束后关闭回环监听、线程和临时核心进程。

本地 GitHub 工作流源码已经更新；尚未提交/推送，也没有把远端 GitHub Actions 描述为已运行通过。

## 实际验证结果与边界

| 验证 | 结果 |
|---|---|
| Windows 官方 26.9.9 真实核心实验 | 最终 36/36 通过 |
| Debian 官方 26.10.31 真实核心实验 | 最终 36/36 通过，包含 UDP 出口源地址与私网阻断证据 |
| Debian 隔离回归，26.10.31 | unit、exits、product-r2、core-r2、install-r2、transactions、ui、archive、prune、reporting、manager、self-update、running-version 全部通过；不修改正式服务 |
| 独立 Windows 最终公网 HTTPS/出口 | 诺亚 Direct、VMISS Direct、VMISS Relay、云途 Direct，8/8 通过；使用升级前保存的客户端参数 |
| 独立 Windows 公网 UDP | 上述四路径分别通过 1.1.1.1 和 8.8.8.8 的 UDP DNS 查询，8/8 通过；验证事务 ID、目标、响应标志及回答 |
| 云途整机重启后 | SSH、Xray 自启、内核运行版本、外部 HTTP/UDP 均通过 |
| 三台 doctor、原配置摘要 | 全部通过 |
| 源码/文档检查、ShellCheck、Python 编译检查 | 通过 |

保留一次初始 api.ipify.org 查询超时：同一客户端随后 HTTPS 成功，改用项目既有的 api4.ipify.org 后与最终复测均通过。原始失败没有从本地结果中删除，不能据重试成功宣称切换期间零失败。

这些结果不覆盖 QUIC/HTTP3 的完整应用握手、手机/TUN DNS 泄漏、真实游戏/语音、所有 IPv6/UDP 私网边界、长时间高负载与全地区性能。内核修复依据指定 CVE 和运行包，不是整机漏洞扫描。协议实现本身没有经本项目独立密码学审计。
