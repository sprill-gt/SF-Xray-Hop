# SF-Xray-Hop

> **暂时性实验产物**：v0.2.4 修复公开包干净安装权限问题，已完成 Ubuntu 24.04 入口 → Ubuntu 22.04 实验出口的生命周期验收。出口重启后观察到短暂 TLS 重连错误；GUI 与长期稳定性待验。[实机记录与边界](docs/vps-lifecycle-0.2.4-2026-10-01.md)。

仓库于2026-10-01以 `sprill-gt` 重新建立。请使用下方当前一键命令；旧仓库的提交与发行摘要仅作历史参考。[重建与历史记录说明](docs/repository-2026-10-01.md)。

默认一键直连，需要时再搭建两台 VPS 的链式代理。Bash + jq + 原生 Xray-core，一个正式服务、一个公网入口，两种独立身份。

默认采用 Xray 官方 **Pre**、0-RTT、XHTTP auto、Chrome、TCP 443 和 `archive.archlinux.org`。26.9.9 是已验证协议基线；不是永久安装版本。更换下游保持入口连接参数，新导出链接的名称会反映新出口。

目标平台：Debian 12、Debian 13、Ubuntu 24.04 LTS，amd64，systemd；Ubuntu 22.04 仅实验兼容。当前版本的测试证据见[验收记录](docs/testing.md)，不能用旧版本结果替代新版本部署验收。

实验版一键安装（root，或已配置 sudo 的用户）：

```bash
(set -o pipefail; f=$(mktemp) || exit; trap 'rm -f -- "$f"' EXIT; curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/sprill-gt/SF-Xray-Hop/v0.2.4/install.sh -o "$f" && printf '%s  %s\n' '9abee9a8de5776ab2d5df928c0e916f5100ff3b4c65031a21fc867d0bfec9beb' "$f" | sha256sum -c - >/dev/null && bash "$f" --script-version 0.2.4 --allow-pre-script)
```

此命令明确选择 [v0.2.4 实验发行](https://github.com/sprill-gt/SF-Xray-Hop/releases/tag/v0.2.4)，先核对引导脚本固定摘要，再核对发行清单和完整包摘要；摘要不是独立签名。已取得完整源码／发行包时，在目录运行 `sudo bash install.sh`。正常安装不询问协议参数；交互成功后显示一次直连链接，非交互安装不输出凭据。已有安装复用身份及频道，不自动升级脚本。

在线安装器默认查找项目正式 Release，**尚无正式发行版时明确停止**；维护者固定提交加摘要或指定实验 Release 是显式测试入口，不冒充正式版。[发行与更新方式](docs/operations.md)。

安装后运行 `sudo sfxh`：菜单 **1** 按需建立链式，**3** 查看直连，**4** 查看入口设备链式链接，**8** 更新／回滚脚本。出口 B 的对接链接在菜单1内显示。[双机操作](docs/two-node-guide.md)。

完整卸载：`sudo sfxh uninstall`，输入 `UNINSTALL` 确认；自动化需明确 `--yes`。删除本项目私密备份和安装脚本，不删除其他服务、SSH 或自行克隆的开发目录。

- [文档导航](docs/README.md)
- [R2 实施及验证边界](docs/r2-implementation.md)
- [VMISS中转 → 诺亚落地验收](docs/vps-forward-2026-09-30.md)
- [R2 双 VPS 历史实机测试](docs/vps-r2-2026-09-30.md)
- [命令与菜单](docs/cli.md)
- [系统支持](docs/platforms.md)
- [设计](docs/design.md) · [协议](docs/protocol.md) · [运维](docs/operations.md)
- [上一轮安全审查处理](docs/audit-0.1.3.md)
