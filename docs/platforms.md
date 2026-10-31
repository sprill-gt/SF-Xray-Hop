# 系统支持与安装

## 目标平台

| 系统 | 架构 | 状态 |
|---|---|---|
| Debian 12 | amd64 | 0.2.8 在云途12.12/systemd252通过安装、服务重启、9项服务器验收及6次独立Windows公网请求；整机重启与双跳未测 |
| Debian 13 | amd64 | 0.2.5 在 13.3入口／13.7出口通过干净安装、systemd、双跳、卸载重装、更新回滚及整机重启恢复 |
| Ubuntu 24.04.3 LTS | amd64 | 0.2.4 安装、systemd、双跳及生命周期历史证据通过；0.2.5 未在该系统重新部署 |

当前源码接受以上三个系统；Ubuntu 22.04 仍不支持。已发布 0.2.6 RC 拒绝 Debian 12，恢复适配包含于 0.2.7 RC。Debian 的当前证据见[0.2.5生命周期](archive/vps-lifecycle-0.2.5-2026-10-01.md)，Ubuntu 的历史证据见[0.2.4生命周期](archive/vps-lifecycle-0.2.4-2026-10-01.md)，当前日常试用和转正规则见[0.2.6 RC](archive/release-candidate-0.2.6.md)，不把旧包结果直接当作新包已部署。

发行版从 /etc/os-release 的 ID、VERSION_ID 判断，不通过 ID_LIKE 放行衍生版。Debian 12/13 覆盖其点版本；Ubuntu 24.04.3 的 VERSION_ID 通常为 24.04，检测接受该版本标识，其他 24.04 点版本没有实机验收与支持承诺。需要可操作的 systemd；WSL 和容器检查不算 VPS 验收。

2026-10-31 当前源码恢复 Debian 12 适配；下文是历史范围说明：2026-10-01 收窄支持范围；0.2.5 的安装和 doctor 平台检查拒绝 Debian 12、Ubuntu 22.04 及其点版本。已发布的 v0.2.4 标签和发行包保持原样。历史 Ubuntu 22.04 测试结果继续保留，不作为今后支持承诺。

v0.2.3 干净安装失败的根因是引导解包后的源文件权限与 DynamicUser 不兼容，已在 v0.2.4 修复，并在 Ubuntu 22.04 和 24.04 均通过；不能据此认定 Ubuntu 22.04 太旧。诺亚重启、换核后的首次 TLS 错误在 Debian 13 仍可复现，随后请求恢复；下游 1-RTT 对比也没有消除重启期间的首次超时，不能承诺换系统或修改 RTT 即可修复。详见[当前生命周期记录](archive/vps-lifecycle-0.2.5-2026-10-01.md)。

0.2.8 新增[云途 Debian 12 真实验收](archive/vps-yuntu-0.2.8-20261101.md)，不把该结果扩展为双跳或整机重启证据。

## 两台测试机迁移至 Debian 13

用户已完成系统重装；SSH 实测 VMISS 为 Debian 13.3、诺亚为 Debian 13.7，均为 amd64、systemd。方向保持 **设备 → VMISS 中转／入口 → 诺亚落地／出口 → Internet**。本轮从两台未安装 Xray 的环境重新验收；系统更新不等于吞吐提升或重连问题已修复。以下为以后重装时的操作说明。

1. 重装前保存两台机器当前安装的私密备份，并确认供应商控制台可用。此前生命周期测试的原始备份早于最终重装，不能代替当前凭据备份。
2. 在供应商控制台选择 Debian 13 amd64 的官方最小镜像，干净重装；不要将 Ubuntu 的 APT 源替换为 Debian 来跨发行版升级。
3. 先准备诺亚出口，再准备 VMISS 入口，按双机向导导入诺亚的中转专用链接。全新安装会生成新身份；需要保留已发布入口链接时，须先核对当前状态与恢复方案。
4. 重建 SSH 连接后，核对新主机指纹及真实 OS。使用同一 core、客户端和协议条件复测安装、权限、出口停启、整机重启、事务恢复和双跳，再更新验收矩阵。

Debian 13 官方支持 amd64，支持周期和镜像信息以[官方发行页](https://www.debian.org/releases/trixie/)为准。

## 安装方法

在两台机器的交互 SSH 窗口分别执行[在线 README](https://github.com/sprill-gt/SF-Xray-Hop#readme)的一键命令。正式发行入口解析项目Release清单；维护者实验入口明确固定完整源码提交与SHA256，不从浮动main执行代码。

正式发行入口需要curl和jq，当前源码缺少jq时先刷新现有APT索引，任一源刷新失败即停止，再按需安装jq；不执行整机升级；固定源码入口也支持wget。没有sudo的普通用户需要切换root。脚本从GitHub HTTPS下载命令指定提交的完整源码，核对 SHA256、包结构和管理器版本后才执行，不依赖git。来源记录保存在安装版本目录的 source.json；status 显示源码提交。临时源码在退出／失败／取消后清理。管道中的安装会重新连接当前终端供数字菜单输入；没有交互终端时使用安装默认值，不输出凭据；无法确定公网地址等必要信息则报错，不能等待输入。

当前 README 和双机向导使用 `bash <(curl -fsSL 固定版本或提交的URL)`，需要 Bash、curl 和可用的 /dev/fd。引导脚本通过 GitHub HTTPS 获取，不额外校验其摘要；完整源码包仍检查 SHA256、结构、大小及版本。旧版生成的长命令保持历史行为。Debian 12 使用 README 中的 0.2.8 RC 远程命令，或从完整源码运行 `bash install.sh`。核心安全检查要求systemd可以建立私有网络／挂载空间及本机IPv6回环，无需修改主机DNS、防火墙或公网端口。

首次运行直接进入本机安装；完成后在交互终端显示直连链接，可跳过重命名。已有安装时进入管理菜单，不重复安装或更新管理程序。保留配置卸载后的恢复仍沿用原身份。管理程序版本更新不在重复安装命令中静默执行。

开发或离线方式仍支持：克隆 `https://github.com/sprill-gt/SF-Xray-Hop.git` 或解压完整发行包，进入目录执行 `sudo bash install.sh`。也可直接调用 `sudo bash sf-xray-hop install --address 203.0.113.10 --rtt 1 --target auto`。

正常安装不询问端口、RTT、名称或角色，直接使用443／0-RTT／archive.archlinux.org。端口冲突、默认目标失败或公网地址不明时才提示处理。上方及下方示例的 `--target auto` 是主动启用候选检测，省略该参数即使用默认域名。已有非本项目 Xray、xray.service、配置或占用端口时停止，不自动接管。

固定初始验收核心示例（地址是文档保留地址，执行前替换）：

```bash
sudo bash install.sh --address 203.0.113.10 --port 443 --rtt 1 --target auto --version 26.9.9
```

默认比较正式版与 Pre 的数字版本，选择较大者，同号优先正式版；状态记录实际选中的 pre/stable；指定 `--version` 进入 pinned。依赖和核心仍需联网下载，“发行包安装”只表示管理脚本来自本地包，不表示完全离线安装。至少预留512 MiB空间；保留多个核心和备份后要继续监测可用空间。

核心更新在下载前也检查临时目录和归档所在文件系统的空间。固定提交与预先给定的摘要提供版本绑定和内容完整性；它们不等于独立签名。本项目尚未配置独立签名信任根，首次发布命令仍依赖其获取渠道与 GitHub HTTPS。

公网单一监听使用 IPv6 双栈地址 `::`，由系统提供 IPv4 映射接入；v1 要求系统没有禁用 IPv6 双栈监听。URI 支持域名、IPv4、方括号 IPv6。系统只绑定 IPv6 或禁用 IPv6 时，不猜测成功，须先在部署验收中检查两种地址的实际可达性。云 NAT、公网域名和安全组是否正确最终由独立设备确认。

## 依赖与系统边界

按需安装官方源中的 bash、jq、curl、ca-certificates、unzip、openssl、coreutils、util-linux、iproute2、procps、iputils-ping。不整机升级，不删 APT 锁。锁超时、源不可用、缺包分别报告。沿用系统 DNS 和现有防火墙，检查云厂商入站 TCP 监听端口；不改 SSH，不关闭 AppArmor。

正式 service 使用专用用户。管理命令使用 sudo。配置权限、低端口能力和 systemd hardening 按声明系统分别验证。业务代码以共同可用的 Bash/jq 能力为下限。

使用现有 APT 配置，不替换软件源；任一源更新失败都会停止依赖安装。不依赖 net-tools、固定网卡名或 resolv.conf 重写。命令进程使用 UTF-8 locale，APT／ping 等解析单独固定为 C，不修改系统全局语言。

systemd 使用专用 `sfxray` 用户、`CAP_NET_BIND_SERVICE`、root 启动准备程序、只读系统目录与专用可写路径。正式服务依赖 network-online；启动准备程序校验归档和代次并恢复中断事务。安装时执行 unit 校验和正式链路复测；开机恢复测试需实际重启该 VPS，不能以 `enable` 成功替代。

临时 Xray 候选、客户端、TLS 检测和测速客户端通过 systemd-run 的 DynamicUser 运行，有效能力为空。LoadCredential 向当前临时用户提供私密配置，管理目录保持0700；临时单元只监听回环、设置运行时限并按控制组结束。0.2.5 已在两台 Debian 13 的 systemd 257 实机完成隔离权限回归。历史 Ubuntu 24.04 的 systemd 255 证据保留；Ubuntu 22.04 的 systemd 249 记录不扩展当前支持范围。

官方来源：[Ubuntu 24.04](https://releases.ubuntu.com/24.04/)（核对日期：2026-09-28）、[Debian 13](https://www.debian.org/releases/trixie/)及[发行说明](https://www.debian.org/releases/trixie/release-notes/)（核对日期：2026-10-01）。
