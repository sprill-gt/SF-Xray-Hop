# SF-Xray-Hop

一键直连，按需搭建双机链式。Bash + jq + 原生 Xray-core；amd64、systemd，支持 Debian 12/13 和 Ubuntu 24.04 LTS。

默认 TCP 443、0-RTT、Chrome、XHTTP auto、REALITY 目标 `archive.archlinux.org`。核心默认跟随最新（含 Pre），可在菜单 **6 → 5** 改为仅正式版；缺少跟随字段的旧安装保持原行为。BBR 默认关闭，可在 **5 → 3** 自选开启或恢复。

## 安装

**v1.1.0 正式版**。完整源码也可直接执行 `sudo bash install.sh`。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sprill-gt/SF-Xray-Hop/v1.1.0/install.sh)
```

固定版本 HTTPS 引导；完整包校验发行清单和 SHA256。非交互安装不输出凭据。可选 `--core-track stable`、`--bbr on`；默认不修改系统拥塞控制。旧安装迁移到本版需使用相同入口追加 `--upgrade-manager`，参见[运维](docs/operations.md)。

## 使用

运行 `sudo sfxh`：

| 菜单 | 用途 |
|---|---|
| 1 / 2 | 配置 / 管理链式 |
| 3 | 分享链接和客户端 JSON |
| 4 / 5 | 节点 / 连接设置，BBR 为可选项 |
| 6 | 核心更新、指定版本、恢复及更新跟随 |
| 7 / 8 | 检测与日志 / 更新管理脚本 |
| 9 | 卸载，输入 UNINSTALL 确认 |

[命令与菜单](docs/cli.md) · [双机操作](docs/two-node-guide.md) · [文档导航](docs/README.md) · [1.1.0 发行说明](docs/releases/1.1.0.md)

[变更记录](CHANGELOG.md) · [安全报告](SECURITY.md) · [GPL-3.0-only 许可证](LICENSE)。验证范围见[实机记录](docs/live-verification-0.2.10.md)和发行说明；历史记录保存在 [docs/archive](docs/archive)。
