# 协议配置与官方实现审查

后续：用户要求优化后，已执行核心升级、节点C内核修复、节点A BBR 对照及扩展 TCP/UDP 回归，见[实际优化与验收](protocol-optimization-20261101.md)。以下保留变更前审查快照。

日期：2026-11-01（UTC+8）。对象：当前 SF-Xray-Hop 源码，以及 SSH 别名 node-b（节点B）、node-a（节点A）、node-c（节点C）的运行配置。只读检查服务器；未更新核心、修改 sysctl、替换身份或重启服务。

结论：现有 VLESS Encryption + Vision + XHTTP + REALITY 组合正确，26.10.31 的真实核心回归通过；它是合理的通用配置，尚不能认定为每条线路的性能最优。优先处理内核安全维护、已撤回核心和验证基线，再按实际线路做性能对比。

## 当前运行状态

通过遍历 /proc/*/exe 确认实际 Xray 进程与状态中的归档路径相符，执行对应二进制 version 核对版本。systemd 主进程是 Bash 管理器，不能把 MainPID 当作 Xray 本体。

| 项目 | 节点B node-b | 节点A node-a | 节点C node-c |
|---|---|---|---|
| 服务 | active | active | active |
| 实际核心 | 26.10.29 / 0afec66 | 26.10.29 / 0afec66 | 26.10.31 / a4a3dff |
| 角色 | 无下游 | 有下游，Relay 走链式出站 | 无下游 |
| 运行内核包 | 6.12.113-1 | 6.12.113-1 | 6.1.158-1 |
| 拥塞控制 / 默认 qdisc | bbr / fq | cubic / fq_codel | bbr / fq |
| net.mptcp.enabled | 1 | 1 | 1 |
| NTP 已同步 | 是 | 是 | 是 |

三台共同参数：ML-KEM-768 认证、mlkem768x25519plus.native、0rtt、chrome、XHTTP auto、8 字节随机 shortId、长度 17 的随机路径、archive.archlinux.org:443。不记录 UUID、私钥、完整 Encryption、路径或分享链接。

## 优先发现

1. **高优先：节点C运行内核低于 Debian 当前列出的修复版本。** 本轮读取的 [Debian CVE-2026-98432 跟踪页](https://security-tracker.debian.org/tracker/CVE-2026-98432)列出 bookworm 的修复版本为 6.1.190-1，trixie 为 6.12.113-1。节点B、节点A 的运行包达到该修复版本，节点C为 6.1.158-1。节点C需要核对软件源和安全更新，安装修复内核并重启后核验实际运行版本。本轮没有执行漏洞利用，也没有检查全部内核 CVE。节点C的 26.10.31 默认关闭 Xray MPTCP 监听，可降低相关攻击面，不能代替内核修复。
2. **中优先：节点B、节点A 仍使用官方已撤回的 26.10.29。** [26.10.31 官方发行说明](https://github.com/XTLS/Xray-core/releases/tag/v26.10.31)明确说明默认关闭 MPTCP，并撤回 26.10.29。两台当前内核已达到上述 Debian 修复版本，因此不将“核心旧”直接写成“仍可被该 CVE 攻击”。建议通过已有事务式换核流程迁移到 26.10.31，保留身份，验证旧客户端与现有下游。net.mptcp.enabled=1 仅表示内核允许 MPTCP，不证明每个监听器启用了它。
3. **中优先：CI 的真实二进制基线仍只有 26.9.9。** 应保留最低兼容版本，同时增加当前生产版本 26.10.31，并把真实协议实验加入 CI；现有工作流下载旧核心、运行配置与逻辑测试，没有执行 tests/protocol_lab.py。本轮手工补测通过，不等于后续版本已有持续回归。
4. **性能待测：节点A 的 cubic / fq_codel 与其他两台不同。** 这不是协议错误。可将 BBR / fq 作为对照，在同一客户端、时段、目标下测吞吐、延迟、重传和 CPU 后决定。无需仅为统一参数改变当前系统。

## 逐项判断

| 配置项 | 判断与建议 |
|---|---|
| VLESS Encryption | 保留。26.10.31 官方生成器仍输出本项目使用的四段格式；ML-KEM-768 配对与解析实测通过。较长分享链接是认证公钥的成本，不应为缩短链接删掉 Encryption。 |
| native 外观 | 保留。外层已有 REALITY 与 XHTTP；没有证据表明换成 xorpub/random 会改善当前线路。 |
| 0rtt / 600s 票据 | 与当前官方生成器一致。它是 VLESS 自身的票据恢复与防重放机制，不能直接套用 TLS 0-RTT 的结论；首次连接仍需协商。1rtt 可作为更严格的逐连接协商选择，会增加延迟，不能宣称全面更优。[官方设计](https://github.com/XTLS/Xray-core/pull/5067) |
| Vision + XHTTP | 组合有效，前提是保持 Encryption。官方实现对非 RAW 传输限制穿透与 Splice；不能把 RAW + Vision 的零拷贝收益直接算给本配置。 |
| XHTTP auto | 保留。26.10.31 的 dialer.go 中，REALITY 且没有 downloadSettings 时 auto 选择 stream-one，HTTP 版本固定为 H2。无需重复强写 stream-one 或添加 TLS 的 alpn；当前也不是 H3。 |
| XMUX、padding 等默认值 | 继续继承核心默认。官方建议一般只填 path。高并发吞吐可对比 XMUX maxConcurrency=1 与默认值，但可能增加 TCP/TLS 连接成本；没有实测前不写入通用模板，也不叠加普通 VLESS Mux。[官方 XHTTP 说明](https://github.com/XTLS/Xray-core/discussions/4113) |
| chrome 指纹 | 合理，保留。Firefox/Safari 在本次原生核心实验中也通过，但不代表实际设备、运营商下更好。 |
| shortId / path / UUID | 8 字节随机 shortId、随机路径、Direct/Relay 独立 UUID 合理。路径与 shortId 不替代认证；无需为追求“最强”定期轮换导致客户端失效。 |
| REALITY target / SNI | 三台当前都通过带 SNI 的 TLS 1.3、证书校验与 H2。无 SNI 握手失败是目标站行为，当前客户端带 SNI，因此不是安装失败。固定目标易维护，但并非经过各 VPS 的网络邻近性择优。可以按实际网络、证书与可达性评估更合适目标。 |
| 后量子范围 | 三台 tls ping 均显示目标仅用 X25519，Post-Quantum=false，证书链总长 3399。内层 VLESS 的 ML-KEM-768 仍成立，但不能称为外层 REALITY 也已完成后量子协商。当前未启用 mldsa65；官方要求启用时目标证书足够大，并建议配合后量子密钥交换，不能直接增加一个字段便宣称完整提升。[REALITY 文档](https://xtls.github.io/config/transports/reality.html) |
| REALITY 回落限制 | 当前没有限速。不要直接全局硬编码 limitFallbackUpload/Download；官方指出限速本身可形成特征。若发现未认证回落消耗流量，应结合目标选择与实际监控处理。 |
| maxTimeDiff / 版本限制 | 当前未设置。三台时钟已同步，但没有客户端时钟证据；不盲目设置很小时间窗。REALITY 的 minClientVer 也不能代替实际客户端功能兼容测试。 |
| 路由与下游失败 | 保留。第一出站 blackhole、按认证用户显式路由；Direct 始终走本机，Relay 有下游时只走下游。当前源码没有链式失败后偷偷切回本机的规则，真实实验也通过。 |
| Freedom 私网保护 | 保留官方默认 finalRules，不添加宽泛 allow。已有安装/更新门槛验证 TCP 私网样本；不等于完整 UDP、DNS 重绑定或全部未来版本安全审计。 |
| DNS / sniffing | 当前继承系统解析与 AsIs，不启用 sniffing。对这套按用户分流的服务器配置是合理的；无需仅为“参数齐全”添加嗅探或硬编码公共 DNS。客户端 DNS/TUN 是否泄漏需独立测试，服务器模板无法证明。 |
| UDP / QUIC | 普通 xtls-rprx-vision 出站在官方源码中有拒绝直接 UDP/443 请求的分支；本项目没有导出 -udp443 变体。真实 UDP/XUDP/客户端 QUIC 回退尚未验证，不能按 TCP HTTPS 通过推定游戏、语音、QUIC 均最佳。 |
| 核心版本选择 | auto 比较正式版和 Pre 是项目明确策略；它追求新版本，不等于稳定性优先。生产变更若需要更可预测，可显式选 stable，并在预检后升级；不擅自改变现有用户策略。 |

## 本轮验证

- 下载官方 26.10.31 Windows amd64 ZIP，并与官方 .dgst 中的 SHA256 比对通过。ZIP SHA256：2e04a9995a6f2ad1b28c0bb25c708ecb2695e43a1c9c7889c4b6ac2b48cf7a6a。
- tests/protocol_lab.py：26 项真实核心检查通过；覆盖 0/1-RTT、单跳/双跳、三种指纹、链式故障不直出、更换和取消出口、旧认证继续有效。实验仅使用回环监听及测试专用 HTTPS 接收器。
- 使用同一 26.10.31 二进制运行 tests/unit.sh：39 项通过，包含真实生成器解析、服务端/客户端/双跳配置校验、URI 回环与非法参数拒绝、RTT 切换保留身份。
- 三台真实服务器的 active、实际二进制版本、配置摘要、运行内核包、sysctl、NTP，以及从各服务器发起的目标 TLS 检测通过读取或探测取得。
- tests/check.py：39 个脚本语法、LF、文档链接/命令、明显凭据扫描和禁止 eval 检查通过。

没有执行：生产换核、内核升级或重启、吞吐压测、跨运营商长期测试、GUI/TUN/手机验证、UDP 负向安全实验、完整官方核心密码学/源码安全审计。原生核心短时回归与目标 TLS 成功不等于以上验证。

## 固定版本官方源码依据

审查按部署候选版本读取源码，不用持续变动的文档示例强制迁移旧字段；26.10.31 仍支持当前 network / clients / password 等字段。

- [vlessenc 生成器](https://github.com/XTLS/Xray-core/blob/v26.10.31/main/commands/all/vlessenc.go)：算法、认证组、native、600s、0rtt。
- [VLESS 配置解析](https://github.com/XTLS/Xray-core/blob/v26.10.31/infra/conf/vless.go)：Encryption、padding 和多密钥的官方能力。项目明确采用四段单组子集，不宣称支持全部高级格式。
- [VLESS outbound](https://github.com/XTLS/Xray-core/blob/v26.10.31/proxy/vless/outbound/outbound.go)：非 RAW 的 Splice 限制与 UDP/443 分支。
- [XHTTP dialer](https://github.com/XTLS/Xray-core/blob/v26.10.31/transport/internet/splithttp/dialer.go)：auto 模式和 REALITY H2。
- [REALITY 配置解析](https://github.com/XTLS/Xray-core/blob/v26.10.31/infra/conf/transport_security.go)：target、密钥、shortId、版本/时间与后量子字段。
- [系统监听器](https://github.com/XTLS/Xray-core/blob/v26.10.31/transport/internet/system_listener.go)：默认 SetMultipathTCP(false)。
- [Freedom](https://github.com/XTLS/Xray-core/blob/v26.10.31/proxy/freedom/freedom.go)：默认最终规则与解析/连接路径的限制。
