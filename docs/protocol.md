# 协议与源码依据

核对日期：2026-09-28。初始基线：[Xray-core v26.9.9](https://github.com/XTLS/Xray-core/releases/tag/v26.9.9)。源码 commit 前缀 52a412d。下述为源码依据，实际二进制结果另见测试记录。

## Encryption、Vision 与 RTT

[vlessenc 源码](https://github.com/XTLS/Xray-core/blob/v26.9.9/main/commands/all/vlessenc.go) 输出 X25519 与 ML-KEM-768 两组认证参数，本项目选择后者，decryption/encryption 必须来自同一组。当前输出握手算法 mlkem768x25519plus、外观 native、服务端 600s、客户端 0rtt。业务算法标识取自输出，未知结构拒绝猜测。

[官方实现说明](https://github.com/XTLS/Xray-core/pull/5067) 说明启用 VLESS Encryption 后 Vision 可与 XHTTP 等传输组合；不能直接套用旧版无 Encryption 的限制，也不承诺 RAW 的 Splice 性能。

R2 默认0-RTT：使用生成器提供的票据期限并导出 0rtt。本机 RTT 与保存的下游 RTT 独立；修改下游只替换已识别参数第三段，能否复用由B的服务端票据策略决定。1-RTT：服务端票据期限设为 0s、客户端设为 1rtt。切换保留认证密钥和 UUID，重建参数并测试。已导入客户端不会自动采用新的客户端选项。0-RTT 不等于整条网络连接没有延迟。

Encryption 的 native/xorpub/random 与 uTLS 指纹完全不同；界面和字段分别处理。指纹明确为 chrome，XHTTP mode 为 auto，不生成额外 XMUX 参数。

## 分享字段

依据：[官方 URI 规范](https://github.com/XTLS/Xray-core/discussions/716)。

| URI | Xray |
|---|---|
| UUID、主机、端口 | VLESS id、address、port |
| encryption、flow | VLESS encryption、flow |
| type=xhttp、security=reality | streamSettings network、security |
| sni、fp、pbk、sid | REALITY serverName、fingerprint、password、shortId |
| path、mode | xhttpSettings path、mode |

百分号只解码一次，+ 不转空格。严格校验重复字段、非法编码和不支持参数。语义 round-trip 必须完整保留身份与连接参数，不要求参数顺序相同。标准 URI 不提供可认证的远端“Relay 身份”或拓扑证明。

## Target 与能力检测

[tls ping 源码](https://github.com/XTLS/Xray-core/blob/v26.9.9/main/commands/all/tls/ping.go) 需要解析实际握手结果，不能只看退出码。还要验证证书、TLS 1.3、H2、实际代理握手。

首次初始化解析生成器参数对；常规更新只检查命令能力，保留长期参数，再验证配置、实际启动、旧客户端→新核心以及新核心→现有下游。未知格式拒绝提交，URI 规范适配需要显式维护，不能靠版本号自动推测。

当前 `x25519` 的公钥输出标签为 `Password (PublicKey)`，适配器解析这个标签；REALITY 客户端 JSON 使用 `password`，URI 仍使用规范字段 `pbk`。依据：[密钥命令](https://github.com/XTLS/Xray-core/blob/v26.9.9/main/commands/all/curve25519.go)、[REALITY 配置](https://github.com/XTLS/Xray-core/blob/v26.9.9/infra/conf/transport_security.go)。vlessenc 的命令实测与两种 RTT 的运行结果见[测试记录](testing.md)。

安装默认伪装域名为 `archive.archlinux.org`，由独立模块读取 `data/reality-targets.txt` 的首个有效条目。交互和非交互省略 `--target` 均直接使用该域名，正常安装不提问；检测失败不静默更换。显式选择 Auto 时才依次检测完整候选列表。两种方式均完成基础 TLS 与真实代理握手、HTTPS、出口请求，再持久化通过的域名，普通启动不重新选择。未来 core 可能更改默认行为；格式未知时停止更新，维护适配器后重验。

26.9.9 的 freedom 默认规则会阻止私网目的地，参见 [freedom 实现](https://github.com/XTLS/Xray-core/blob/v26.9.9/proxy/freedom/freedom.go) 与 [finalRules 配置](https://github.com/XTLS/Xray-core/blob/v26.9.9/infra/conf/freedom.go)。生产模板沿用这个默认行为。本地协议测试只在测试配置放行测试 HTTPS 接收器的精确回环地址和端口，不能把该放行复制到公网模板。

2026-10-01核对：[26.3.27的freedom实现](https://github.com/XTLS/Xray-core/blob/v26.3.27/proxy/freedom/freedom.go)没有同样的默认final-rule路径，配置可启动并不表示安全行为等价。0.2.3在核心应用前增加隔离负向行为检查，26.3.27被拒绝。26.9.9源码包含字面IP、解析结果及实际连接地址检查，另有UDP路径；本版自动门槛实测的是TCP样本，不将它表述为完整UDP、DNS重绑定或未来核心安全审计。详情见[审查修正](audit-0.2.2.md)。

## 指定GUI版本的源码核对

2026-10-01按用户提供的版本核对：Windows v2rayN 7.25.2、Android v2rayNG 2.3.8，客户端核心均为26.9.9。两者固定版本的VLESS解析器都读取`encryption`；公共解析器读取XHTTP的`type/path/mode`以及REALITY的`sni/fp/pbk/sid`和`flow`。没有据此改变分享字段或删除Encryption。来源：[v2rayN VLESSFmt](https://github.com/2dust/v2rayN/blob/7.25.2/v2rayN/ServiceLib/Handler/Fmt/VLESSFmt.cs)、[BaseFmt](https://github.com/2dust/v2rayN/blob/7.25.2/v2rayN/ServiceLib/Handler/Fmt/BaseFmt.cs)、[v2rayNG VlessFmt](https://github.com/2dust/v2rayNG/blob/2.3.8/V2rayNG/app/src/main/java/com/v2ray/ang/fmt/VlessFmt.kt)、[FmtBase](https://github.com/2dust/v2rayNG/blob/2.3.8/V2rayNG/app/src/main/java/com/v2ray/ang/fmt/FmtBase.kt)。这是字段级源码核对，实际GUI长链接导入、自定义JSON、客户端DNS和故障重连仍待设备验收。

已验证 URI 完整语义回环，但第三方 GUI 对长 Encryption 字段、Vision 与 XHTTP 的支持仍需逐版本验证；不据此宣称 v2rayN 或所有客户端已兼容。

R2 核对日期：2026-09-30。参考 [VLESS outbound](https://xtls.github.io/config/outbounds/vless.html) 与 [inbound](https://xtls.github.io/config/inbounds/vless.html)。未知 Encryption 结构停止 RTT 修改；不自行扩展算法或证明其安全性。
