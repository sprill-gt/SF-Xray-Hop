# SF-Xray-Hop

> **v0.2.6 发布候选版（RC）／日常试用阶段**：双机生命周期验收已通过，客户端与日常体验由用户验收后决定转正。维护重启时可能短暂断连，随后自动恢复。[RC 说明](docs/release-candidate-0.2.6.md) · [实际验收记录](docs/vps-lifecycle-0.2.5-2026-10-01.md)。

仓库于2026-10-01以 `sprill-gt` 重新建立。请使用下方当前一键命令；旧仓库的提交与发行摘要仅作历史参考。[重建与历史记录说明](docs/repository-2026-10-01.md)。

默认一键直连，需要时再搭建两台 VPS 的链式代理。Bash + jq + 原生 Xray-core，一个正式服务、一个公网入口，两种独立身份。

默认采用 Xray 官方 **Pre**、0-RTT、XHTTP auto、Chrome、TCP 443 和 `archive.archlinux.org`。26.9.9 是已验证协议基线；不是永久安装版本。更换下游保持入口连接参数，新导出链接的名称会反映新出口。

支持范围仅声明 **Debian 13 和 Ubuntu 24.04.3 LTS**，amd64，systemd。当前版本的实机证据与历史版本分别记录，不再支持 Debian 12、Ubuntu 22.04。[系统支持与迁移](docs/platforms.md) · [验收记录](docs/testing.md)。

RC 一键安装（root，或已配置 sudo 的用户）：

```bash
(set -o pipefail; f=$(mktemp) || exit; trap 'rm -f -- "$f"' EXIT; curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/sprill-gt/SF-Xray-Hop/v0.2.6/install.sh -o "$f" && printf '%s  %s\n' '70c59720c9816df6763e730fb205b3b671f16496e818b89e5967707c207afc5e' "$f" | sha256sum -c - >/dev/null && bash "$f" --script-version 0.2.6 --allow-pre-script)
```

此命令明确选择 [v0.2.6 RC](https://github.com/sprill-gt/SF-Xray-Hop/releases/tag/v0.2.6)，先核对引导脚本固定摘要，再核对发行清单和完整包摘要；摘要不是独立签名。已取得完整源码／发行包时，在目录运行 `sudo bash install.sh`。正常安装不询问协议参数；交互成功后显示一次直连链接，非交互安装不输出凭据。已有安装复用身份及频道，不自动升级脚本。

在线安装器默认查找项目正式 Release，**尚无正式发行版时明确停止**；维护者固定提交加摘要或指定实验 Release 是显式测试入口，不冒充正式版。[发行与更新方式](docs/operations.md)。

安装后运行 `sudo sfxh`：菜单 **1** 按需建立链式，**3** 查看直连，**4** 查看入口设备链式链接，**8** 更新／回滚脚本。出口 B 的对接链接在菜单1内显示。[双机操作](docs/two-node-guide.md)。

查看当前脚本版本：`sfxh version`；自动化使用 `sfxh --version`。主菜单顶部及更新页也显示脚本版本，与 Xray 核心版本分开。已有安装更新 RC：`sudo sfxh self update --version 0.2.6 --allow-pre`。

完整卸载：`sudo sfxh uninstall`，输入 `UNINSTALL` 确认；自动化需明确 `--yes`。删除本项目私密备份和安装脚本，不删除其他服务、SSH 或自行克隆的开发目录。

- [文档导航](docs/README.md)
- [R2 实施及验证边界](docs/r2-implementation.md)
- [VMISS中转 → 诺亚落地验收](docs/vps-forward-2026-09-30.md)
- [R2 双 VPS 历史实机测试](docs/vps-r2-2026-09-30.md)
- [命令与菜单](docs/cli.md)
- [系统支持](docs/platforms.md)
- [设计](docs/design.md) · [协议](docs/protocol.md) · [运维](docs/operations.md)
- [上一轮安全审查处理](docs/audit-0.1.3.md)
