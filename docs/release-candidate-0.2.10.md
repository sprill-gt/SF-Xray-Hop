# v0.2.10 RC（待发布）

日期：2026-11-01（UTC+8）。本次未连接、部署或重启任何生产服务器；未创建 0.2.10 tag 或 Release。草稿 [PR #1](https://github.com/sprill-gt/SF-Xray-Hop/pull/1) 包含源码及验证。

## 改动

- 保存 `core.track=latest|stable`。默认 latest（正式版与 Pre 比较），菜单 6 → 5 可切换为仅正式版；只改元数据，不重启、不换核。缺少字段的旧状态仍按 latest，当前版本来源继续保存在 core.channel；显式单次频道选择不覆盖 track。
- 新增撤回版本清单，拒绝自动及手动选择 Xray 26.10.29，doctor/check 对现有版本只提示主动更新。
- 默认 REALITY 目标继续为 archive.archlinux.org。Encryption/native、RTT/ticket、Chrome、Vision、XHTTP auto、服务端 REALITY 和路由结构保持。
- 导出的客户端配置提供 HTTP 10809 与 SOCKS5 10808（UDP 开启）；UDP/443 在本地黑洞，内部探测保持单端口 HTTP。
- systemd 沙箱进一步加固。已知旧 unit 通过摘要识别，升级事务备份并原子替换 unit、daemon-reload；失败/中断恢复旧单元及脚本，不重启运行核心。自定义单元仍拒绝覆盖。0.2.9 首次迁移需通过新版引导入口追加 --upgrade-manager。
- BBR 为显式可选项，默认关闭；菜单 5 → 3、tune bbr on/off/status 或新装 --bbr on。检查内核和模块能力，记录原值及文件摘要；失败/卸载恢复，拒绝覆盖外部修改。不会替换内核或执行 233boy 远程脚本。
- Debian 12/13 引导矩阵、共享静态检查、双核心真实协议测试；tag 工作流生成候选包、清单、证明与草稿发行，留给维护者发布。
- GPL-3.0 许可，增加 SECURITY/CHANGELOG，历史记录归档；v* 标签已禁止更新和删除（规则 26285191，无绕过角色）。

`model.jq` 变化会改变 policySha256，下次安全检查/换核将重新执行隔离门禁，不会因为历史缓存而跳过。

## 已验证

[Linux CI 41236338257](https://github.com/sprill-gt/SF-Xray-Hop/actions/runs/41236338257) 在提交 d3c773e 上四项矩阵通过：

- Debian 12（jq 1.6）和 Debian 13 引导、静态检查、核心选版及 BBR 模拟边界。
- Ubuntu 24.04 runner + 官方核心 26.9.9 / 26.10.31：41 项单元检查、25 项事务检查、20 项 UI 检查，以及归档、清理、脚本升级/回滚、运行版本、引导和 BBR 模拟回归通过。单元迁移和 SIGKILL 后精确恢复通过。
- systemd-analyze verify 和离线 exposure 对照通过：原始 0.2.9 为 6.3，新模板为 1.5；CI 门槛设为 15（十分之一分单位）。
- 真实临时 systemd DynamicUser/无 capability 探测通过；两个核心各完成 30 个 TCP 私网/CGNAT/0.0.0.0 及 2 个 UDP 身份 canary，旧核心 26.3.27 被拒绝，缓存失效重测和清理通过。未改变正式服务 PID。
- 两个 Linux 核心各 38 项真实回环协议检查通过，覆盖 0/1-RTT、双跳、下游故障拒绝直出、UDP 和导出客户端 UDP/443 本地阻断。
- 本地 Windows 26.10.31 同样通过 38 项真实协议检查；ShellCheck、LF、语法、文档链接及凭据扫描通过。

## 最终验证与边界

[最终源码 CI 41236732937](https://github.com/sprill-gt/SF-Xray-Hop/actions/runs/41236732937) 在 a3c0879 上四项矩阵通过，并新增通过 `tests/runtime-sandbox.sh`：一次性 Ubuntu 24.04 runner 的真实加固主进程启动/重启、root 预启动恢复、非 root 核心、仅 CAP_NET_BIND_SERVICE、配置和运行目录只读、日志写入。该检查使用回环 HTTP fixture 验证沙箱，协议另由双核心真实回环实验室验证。

Debian 12/13 的完整真实 systemd install → restart → core update → rollback → uninstall 生命周期尚未验收；当前 Debian 矩阵为引导/逻辑测试，不能替代这项证据。

BBR 的真实内核持久化、不同虚拟化环境、重启后恢复尚未实测；当前为可恢复逻辑和所有权边界测试。未测公网设备或生产链路。发行/attestation 工作流尚未由正式 tag 触发，不能宣称已经生成可公开验证的发行证明。可选的每周跟随上游浮动核心任务未启用。
