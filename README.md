# SF-Xray-Hop

> **v0.2.8 发布候选版（RC）**：核心版本查询改用轻量标签索引，只核对候选 Release，并增加进度、压缩和超时错误。保留正式版与 Pre 取较大版本的规则。[RC 说明](docs/release-candidate-0.2.8.md) · [实际验收记录](docs/vps-lifecycle-0.2.5-2026-10-01.md)。

仓库于2026-10-01以 `sprill-gt` 重新建立。请使用下方当前一键命令；旧仓库的提交与发行摘要仅作历史参考。[重建与历史记录说明](docs/repository-2026-10-01.md)。

默认一键直连，需要时再搭建两台 VPS 的链式代理。Bash + jq + 原生 Xray-core，一个正式服务、一个公网入口，两种独立身份。

默认比较 Xray 官方 **正式版与 Pre，选择数值更大的版本**、0-RTT、XHTTP auto、Chrome、TCP 443 和 `archive.archlinux.org`。26.9.9 是已验证协议基线；不是永久安装版本。更换下游保持入口连接参数，新导出链接的名称会反映新出口。

核心默认安装、检查及更新都会比较正式版与 Pre，按数字版本取较大者，同号优先正式版；手动选版本用 `sudo sfxh core select 26.9.9`，最低 26.9.9。菜单9更新最新核心，10输入版本号，11恢复历史核心，12卸载。[命令说明](docs/cli.md)。

当前源码适配 **Debian 12/13 和 Ubuntu 24.04.3 LTS**，amd64，systemd。Debian 12.12 已在云途通过真实安装、服务重启、9项服务器检查与6次独立Windows公网请求；旧版 0.2.6 RC 仍拒绝 Debian 12，请使用下方 0.2.8 命令。Ubuntu 22.04 不在支持范围。[系统支持与迁移](docs/platforms.md) · [本次云途验收](docs/vps-yuntu-0.2.8-20261101.md) · [验收记录](docs/testing.md)。

RC 远程 Bash 安装命令（root，或已配置 sudo 的用户）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sprill-gt/SF-Xray-Hop/v0.2.8/install.sh) --rc
```

此命令明确选择 [v0.2.8 RC](https://github.com/sprill-gt/SF-Xray-Hop/releases/tag/v0.2.8)，通过 HTTPS 执行固定版本引导脚本，再由安装器核对发行清单和完整包摘要；该简短入口不再额外校验引导脚本摘要。已取得完整源码／发行包时，在目录运行 `sudo bash install.sh`。正常安装不询问协议参数；交互成功后显示一次直连链接，非交互安装不输出凭据。已有安装复用身份及频道，不自动升级脚本。

`--rc` 明确选择引导脚本对应的 RC，不会安装旧版 0.2.6。已有完整源码也可以在目录执行：

```bash
bash install.sh
```

在线安装器默认查找项目正式 Release，**尚无正式发行版时明确停止**；维护者固定提交加摘要或指定实验 Release 是显式测试入口，不冒充正式版。[发行与更新方式](docs/operations.md)。

安装后运行 `sudo sfxh`：菜单 **1** 按需建立链式，**3** 查看直连，**4** 查看入口设备链式链接，**8** 更新／回滚脚本。出口 B 的对接链接在菜单1内显示。[双机操作](docs/two-node-guide.md)。

查看当前脚本版本：`sfxh version`；自动化使用 `sfxh --version`。主菜单顶部及更新页也显示脚本版本，与 Xray 核心版本分开。已有安装更新 RC：`sudo sfxh self update --version 0.2.8 --allow-pre`。

完整卸载：`sudo sfxh uninstall`，输入 `UNINSTALL` 确认；自动化需明确 `--yes`。删除本项目私密备份和安装脚本，不删除其他服务、SSH 或自行克隆的开发目录。

- [文档导航](docs/README.md)
- [R2 实施及验证边界](docs/r2-implementation.md)
- [VMISS中转 → 诺亚落地验收](docs/vps-forward-2026-09-30.md)
- [R2 双 VPS 历史实机测试](docs/vps-r2-2026-09-30.md)
- [命令与菜单](docs/cli.md)
- [系统支持](docs/platforms.md)
- [设计](docs/design.md) · [协议](docs/protocol.md) · [运维](docs/operations.md)
- [上一轮安全审查处理](docs/audit-0.1.3.md)
