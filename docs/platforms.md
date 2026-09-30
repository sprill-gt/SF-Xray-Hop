# 系统支持与安装

## 目标平台

| 系统 | 架构 | 状态 |
|---|---|---|
| Debian 12 | amd64 | 实际部署待验证 |
| Debian 13 | amd64 | 实际部署待验证 |
| Ubuntu 24.04 LTS | amd64 | 24.04.3 实机安装、systemd、双跳通过；当前VMISS中转／入口 |
| Ubuntu 22.04 LTS | amd64 | 实验兼容；实机安装、systemd、双跳通过；当前诺亚落地／出口 |

v0.2.0已在这两台Ubuntu完成GitHub全新安装、systemd、中文向导和Windows独立设备双跳检查；更新、卸载及故障恢复的具体证据见[R2实机记录](vps-r2-2026-09-30.md)。Debian仍是目标支持，不能从Ubuntu结果外推。

Ubuntu 24 指 24.04 LTS 系列点版本。发行版从 /etc/os-release 的 ID、VERSION_ID 判断，不通过 ID_LIKE 放行衍生版。需要可操作的 systemd；WSL 和容器检查不算 VPS 验收。

Ubuntu 22.04 根据用户提供的测试机新增为实验兼容，安装和 doctor 显式提示此状态；没有扩大到 Ubuntu 20.04 或其他衍生系统。当前实机环境为 Bash 5.1／systemd249／jq1.6 与 Bash5.2／systemd255／jq1.7，两端均完成核心协议验证。详细范围及未测项见[验收记录](testing.md)。

## 安装方法

在两台机器的交互 SSH 窗口分别执行[在线 README](https://github.com/sprill-gt/SF-Xray-Hop#readme)的一键命令。正式发行入口解析项目Release清单；维护者实验入口明确固定完整源码提交与SHA256，不从浮动main执行代码。

正式发行入口需要curl和jq，缺少jq时尝试通过现有APT源按需安装；固定源码入口也支持wget。没有sudo的普通用户需要切换root。脚本从GitHub HTTPS下载命令指定提交的完整源码，核对 SHA256、包结构和管理器版本后才执行，不依赖git。来源记录保存在安装版本目录的 source.json；status 显示源码提交。临时源码在退出／失败／取消后清理。管道中的安装会重新连接当前终端供数字菜单输入；没有交互终端时使用安装默认值，不输出凭据；无法确定公网地址等必要信息则报错，不能等待输入。

当前README和双机向导生成的一键命令额外要求curl、mktemp和sha256sum：先下载临时引导文件，核对固定摘要后执行，失败清理并停止。哈希随引导版本更新；不应删掉检查以绕过下载错误。核心安全检查要求systemd可以建立私有网络／挂载空间及本机IPv6回环，无需修改主机DNS、防火墙或公网端口。

首次运行直接进入本机安装；完成后在交互终端显示直连链接，可跳过重命名。已有安装时进入管理菜单，不重复安装或更新管理程序。保留配置卸载后的恢复仍沿用原身份。管理程序版本更新不在重复安装命令中静默执行。

开发或离线方式仍支持：克隆 `https://github.com/sprill-gt/SF-Xray-Hop.git` 或解压完整发行包，进入目录执行 `sudo bash install.sh`。也可直接调用 `sudo bash sf-xray-hop install --address 203.0.113.10 --rtt 1 --target auto`。

正常安装不询问端口、RTT、名称或角色，直接使用443／0-RTT／archive.archlinux.org。端口冲突、默认目标失败或公网地址不明时才提示处理。上方及下方示例的 `--target auto` 是主动启用候选检测，省略该参数即使用默认域名。已有非本项目 Xray、xray.service、配置或占用端口时停止，不自动接管。

固定初始验收核心示例（地址是文档保留地址，执行前替换）：

```bash
sudo bash install.sh --address 203.0.113.10 --port 443 --rtt 1 --target auto --version 26.9.9
```

默认安装频道为 pre；指定 `--version` 进入 pinned。依赖和核心仍需联网下载，“发行包安装”只表示管理脚本来自本地包，不表示完全离线安装。至少预留512 MiB空间；保留多个核心和备份后要继续监测可用空间。

核心更新在下载前也检查临时目录和归档所在文件系统的空间。固定提交与预先给定的摘要提供版本绑定和内容完整性；它们不等于独立签名。本项目尚未配置独立签名信任根，首次发布命令仍依赖其获取渠道与 GitHub HTTPS。

公网单一监听使用 IPv6 双栈地址 `::`，由系统提供 IPv4 映射接入；v1 要求系统没有禁用 IPv6 双栈监听。URI 支持域名、IPv4、方括号 IPv6。系统只绑定 IPv6 或禁用 IPv6 时，不猜测成功，须先在部署验收中检查两种地址的实际可达性。云 NAT、公网域名和安全组是否正确最终由独立设备确认。

## 依赖与系统边界

按需安装官方源中的 bash、jq、curl、ca-certificates、unzip、openssl、coreutils、util-linux、iproute2、procps、iputils-ping。不整机升级，不删 APT 锁。锁超时、源不可用、缺包分别报告。沿用系统 DNS 和现有防火墙，检查云厂商入站 TCP 监听端口；不改 SSH，不关闭 AppArmor。

正式 service 使用专用用户。管理命令使用 sudo。配置权限、低端口能力和 systemd hardening 必须在三个系统分别验证。业务代码以共同可用的 Bash/jq 能力为下限。

使用现有 APT 配置，不替换软件源；任一源更新失败都会停止依赖安装。不依赖 net-tools、固定网卡名或 resolv.conf 重写。命令进程使用 UTF-8 locale，APT／ping 等解析单独固定为 C，不修改系统全局语言。

systemd 使用专用 `sfxray` 用户、`CAP_NET_BIND_SERVICE`、root 启动准备程序、只读系统目录与专用可写路径。正式服务依赖 network-online；启动准备程序校验归档和代次并恢复中断事务。安装时执行 unit 校验和正式链路复测；开机恢复测试需实际重启该 VPS，不能以 `enable` 成功替代。

临时 Xray 候选、客户端、TLS 检测和测速客户端通过 systemd-run 的 DynamicUser 运行，有效能力为空。LoadCredential 向当前临时用户提供私密配置，管理目录保持0700；临时单元只监听回环、设置运行时限并按控制组结束。Ubuntu22.04的systemd249和Ubuntu24.04的systemd255已隔离验证，Debian 实机仍待验收。

官方来源：[Ubuntu 24.04](https://releases.ubuntu.com/24.04/)、[Debian 13](https://www.debian.org/releases/trixie/)。核对日期：2026-09-28。
