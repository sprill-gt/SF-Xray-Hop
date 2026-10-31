# 变更记录

## 1.1.0（正式版）

- 核心更新跟随设置 `latest` / `stable` 持久保存，旧状态仍按 latest；撤回版本禁止选择。
- 加固服务模板，已知旧单元可事务迁移并 daemon-reload；不在脚本更新时重启核心。
- 导出 SOCKS5 + HTTP 客户端配置，UDP/443 在本地阻断。
- 受管理 BBR 为可选项，默认不启用，支持恢复与卸载清理。
- Debian 12/13 CI、双核心协议测试、发行证明与 GPL-3.0 许可。
- 固定版本引导默认精确对应自身正式 Release，保留源码离线安装及 RC 兼容入口。
- 完整验证边界见 [1.1.0 发行说明](docs/releases/1.1.0.md)。

0.2.10 为开发阶段编号，功能经隔离 CI 和节点C实测后纳入 1.1.0；未创建 0.2.10 标签。

## 0.2.9

精简彩色菜单，分开链式配置与管理，集中核心版本选择和恢复。[原记录](docs/archive/release-candidate-0.2.9.md)。

## 0.2.8

轻量 tags 索引、有限时长的发行查询与核心 ZIP 断点续传。[原记录](docs/archive/release-candidate-0.2.8.md)。

## 0.2.7

固定 RC 入口、APT 依赖流程和 Debian 12 平台适配。[原记录](docs/archive/release-candidate-0.2.7.md)。

## 0.2.6 / 0.2.5 / 0.2.3

历史候选版的实现和验收边界分别保存在 [0.2.6](docs/archive/release-candidate-0.2.6.md)、[0.2.5](docs/archive/release-candidate-0.2.5.md)、[0.2.3](docs/archive/release-candidate-0.2.3.md)。不把历史部署记录视为当前版本的验收。
