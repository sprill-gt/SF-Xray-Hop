# Argon 建议复核与实施（2026-11-01）

## 审批结论

采纳日志优化、安全门禁扩展、客户端 SOCKS5 导出、多源公网 IPv4 检测、可选 GitHub Token 和服务模板加固。以下判断需要修正：

- `ExecStartPre=+` 对该命令绕过用户、capability 与文件系统命名空间限制（[systemd 官方说明](https://www.freedesktop.org/software/systemd/man/254/systemd.service.html)）。因此保留原锁路径，主进程仅保留绑定低端口 capability，并仅允许写核心日志目录；运行配置只读。无需引入新旧脚本争用不同锁文件的迁移风险。
- 不采用 `/releases/latest` 快路径：现有策略比较全部数字版本标签并核对发布状态，不能用 GitHub latest 的选择语义取代。
- “彻底消除注入风险”“理论最佳”不是可由当前测试证明的结论。本次仅验证列出的边界。

## 实施内容

- Bash 内建 UTC 时间戳；运行日志直接 `printf -v`，避免每行命令替换子 shell；脱敏 `sed -u`。轮转仍按原阈值执行。
- 换核门禁新增 CGNAT `100.100.100.200` 与 `0.0.0.0` TCP canary，总计 30 个 TCP 检查；两个 VLESS 身份各增加一个 UDP 回环 canary。必须出现新 `blocked target: udp:` 日志，超时不能代表通过。缓存校验新增 `udpChecks==2`，策略摘要变化自动废弃旧结果。
- `sfxh view json` 输出回环 HTTP 10809 和 SOCKS5 10808（UDP 开启）；健康探测和测速仍使用原单 HTTP 随机端口。
- 公网地址检测最多查询 ipify、icanhazip、Cloudflare 三个独立提供方，要求两个返回一致 IPv4；过滤私网、CGNAT、文档、基准测试、多播等特殊地址。任何一次失败可以继续，无法形成一致结果仍要求 `--address`。
- `SFXH_GITHUB_TOKEN` 优先于 `GITHUB_TOKEN`，仅向 GitHub API 请求传递；认证头由标准输入交给 curl，避免出现在 curl 进程参数中。发行资产下载不携带 Token。拒绝含控制字符的 Token。
- 服务模板增加设备/内核/cgroup/SUID/personality 加固及文件描述符上限 524288。

## 服务迁移与发行边界

本次只修改本地源码，版本仍为 0.2.9。现有 `sf_manager_compatible` 的服务单元逐字比较保持有效：旧安装通过 `self update` 切换到本次不同单元时会明确拒绝，不会静默改变服务沙箱。新模板可用于新安装；现有安装的正式迁移需要另行完成带回滚的单元迁移与实机验收，本次没有把它伪装成兼容的在线更新。

未更改任何 VPS、未重启正式服务、未提交或发布。已有未提交修改保持。开发归档放在独立 `.cache/argon-package-source/artifacts/`，没有生成绑定某提交的正式 `manifest.json`，也没有覆盖原 artifacts 发行文件。

## 验证

- `tests/check.py`：Shell 语法、LF、文档链接、凭据扫描。
- ShellCheck warning 级别通过（沿用项目排除项）。
- `tests/argon-review.sh`：UTC 内建时间戳、检测单源超时容错/分歧与特殊地址拒绝、Token 传递边界、导出配置实核校验。
- `tests/protocol_lab.py`：官方 26.10.31 Windows 核心，36 项真实回环 TCP/UDP/双跳/故障拒绝测试通过。
- Linux/systemd 的真实隔离门禁、主服务沙箱与旧服务单元迁移尚未验收；Windows 本地通过不能替代这些证据。

补充结果：40 项单元检查通过；`exits`、`product-r2`、`core-r2`、`install-r2`、`ui`、`reporting`、`releases-auto`、`asset-resume`、`bootstrap-dependencies` 返回成功；短启动命令 2 项检查通过。脱敏流在输入管道仍打开时即可输出，验证没有等待 EOF 的缓冲延迟。开发归档完整性检查通过。

环境限制：`archive` 因 Git Bash 缺少 `flock` 失败；`manager`、`self-update` 因缺少 Linux `root:root` 用户/组失败；`running-version` 要求 Linux `/proc`；`prune` 本机未通过。`transactions` 虽打印 24 项通过，但日志出现缺少 `flock`，因此不能作为完整锁与事务验收。以上均不计为通过，也未用替代锁或伪造用户来绕过。
