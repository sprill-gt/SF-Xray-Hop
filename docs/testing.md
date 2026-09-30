# 验收与实际记录

## 状态定义

目标支持不等于安装通过；本机 Xray 连接不等于真实双 VPS 或设备验收。所有结果必须记录命令、时间、OS、core 版本和具体范围。

0.2.3安全修正见[审查处理](audit-0.2.2.md)，公开包实际干净安装失败及0.2.4修正见[生命周期记录](vps-lifecycle-0.2.3-2026-10-01.md)。下列部署矩阵保留历史版本含义，不代表新发行包已完成重新安装。

## 平台矩阵

当前支持范围仅声明 **Debian 13 与 Ubuntu 24.04.3 LTS、amd64**。两台 VPS 已重装为 Debian 13；0.2.5 最终公开候选包按 VMISS 入口 → 诺亚出口重新验收，过程与发布条件见[候选记录](release-candidate-0.2.5.md)。Debian 12、Ubuntu 22.04 的记录仅作历史参考。

### 历史平台证据（0.2.0 至 0.2.4）

当前0.2.4公开包：Ubuntu24.04.3仅作为VMISS入口、Ubuntu22.04仅作为诺亚实验出口，均通过干净安装、升级／回滚、完整卸载、权限、真实事务中断后的整机重启及Windows原生核心双跳检查。落地停启／换核后首批HTTPS曾出现TLS错误，重试恢复；GUI及长期运行未验。[逐项记录、发行摘要与限制](vps-lifecycle-0.2.4-2026-10-01.md)。以下旧版本表格保留历史含义，不扩展当前版本已验范围。

下列概览汇总v0.2.0／0.2.1的[R2真实部署记录](vps-r2-2026-09-30.md)，逐项版本及操作边界以记录为准。整机中断恢复在0.2.0执行；0.2.1追加运行版本修复、在线升级及Ubuntu22.04全新安装。更早的隔离回归保留于文末，不替代实机证据。

VMISS中转 → 诺亚落地的后续失败保留、核心频道与0.2.2脚本验证见[固定方向验收](vps-forward-2026-09-30.md)。这两台的日常用途保持固定，不按历史反向测试交换角色。

| 系统 | 安装 | systemd／服务重启恢复 | 整机重启／断电 | 真实双跳 |
|---|---|---|---|---|
| Debian 12 amd64 | 待验证 | 待验证 | 待验证 | 待验证 |
| Debian 13 amd64 | 待验证 | 待验证 | 待验证 | 待验证 |
| Ubuntu 24.04 amd64 | 24.04.3通过 | 通过 | 重启通过／断电待验证 | 入口、出口均通过 |
| Ubuntu 22.04 amd64（历史实验，现已移出支持） | 通过 | 通过 | 重启通过／断电待验证 | 入口、出口均通过 |

当前支持范围的配对状态（未执行项不得从其他配对推定）：

| 入口＼出口 | Debian 13 | Ubuntu 24.04.3 |
|---|---|---|
| Debian 13 | 0.2.5 验收进行中 | 待验证 |
| Ubuntu 24.04.3 | 待验证 | 待验证 |

历史 Ubuntu 混合双跳见上方记录。当前不再要求原三系统 3×3 矩阵，手机、v2rayN GUI 和日常持续运行仍需独立证据；本机短时检测不作为外部容量结论。

## 必须覆盖

- 两种 RTT 下单跳、双跳、连续连接和核心重启重连；独立 UUID 按 user 路由。
- 长参数、中文、IPv6、特殊字符 round-trip；恶意 URI 和不支持参数拒绝。
- 候选 B2 错误、超时、出口失败保留 B1；替换和取消后入口链接不变。
- 下游掉线 Relay 不偷跑本机出口，Direct 仍可使用。
- core、配置、状态同步恢复，注入配置失败、启动失败、进程终止和断电。
- 声明支持系统的全新／重复安装、依赖缺失、端口占用、权限、卸载和服务恢复。
- 中文数字操作从两端开始，错误输入和中断恢复；短终端、无色、长链接。
- 诊断日志不包含凭据；测试结束无残留进程或公网监听。
- 文档相对链接和命令说明一致，不提交真实秘密。

## 本地执行记录

2026-09-28，Windows 11 专业工作站版10.0.26200／amd64，Git Bash 5.3.15，jq 1.7.1，Python 3.14.7。使用官方下载并核对摘要的 Xray 26.9.9、commit `52a412d`、go1.27.1 windows/amd64。此次没有 Linux systemd 环境。

官方 Windows ZIP SHA256：`244deaba2098c2964e49bba90df3707777e5f5f428a82d2f29604015f24beec2`；解压后 core SHA256：`0d0fc0ea2b05641acb78c01fc36ad694e7b029861b2d5eb93da0e3e9fda9a98f`。这不是 Linux 发行包的摘要。

| 已运行检查 | 结果 | 证据范围 |
|---|---|---|
| tests/unit.sh | 31项通过 | 发行版识别样本、真实生成器输出、配置验证、恶意 URI、完整语义回环、RTT 保留密钥、脱敏 |
| tests/protocol_lab.py | 26项通过 | 官方 core 真实进程，0/1-RTT 下单跳、双跳、三种指纹、Direct 分流、故障不直出、更换／取消出口、旧参数继续认证 |
| tests/transactions.sh | 10项通过 | 提交、候选拒绝、启动／健康失败、TERM、SIGKILL 遗留记录、代次冲突、篡改拒绝 |
| tests/ui.sh | 9项通过 | 中文数字输入、无默认 RTT、跨机提示、保存续接、失败重试、已完成向导保护、非交互错误 |
| tests/check.py | 通过 | 19个 Bash 文件语法、LF、文档链接、命令覆盖、明显凭据扫描、禁止 eval |
| ShellCheck 0.11.0 | warning级通过 | 动态模块导入显式标注；跨模块变量采用 SC2034 排除项 |
| xray tls ping www.amazon.com | SNI握手成功、TLS1.3 | 当前开发机到单个候选的检查，不代表任何 VPS 的 target 可用性 |

真实协议实验启动三个回环服务器与短时客户端，HTTPS 接收器用三种不同回环源地址辨别实际 freedom 出口，验证请求确实经过被选择的出口。实验对其私有 HTTPS 接收器做了测试专用放行，生产模板没有该规则。

事务测试的 systemctl 和网络行为是故障注入替身；Windows 还模拟了 flock、活动 symlink 和 boot/process 身份。因此10项通过不代表 Linux文件系统的断电持久性、服务重启或系统开机恢复已验收。菜单测试模拟业务动作，真实终端窄屏／SSH 断线仍待验证。

## 复现本地检查

开发检查需要 Python、Bash、jq 和自行从官方来源核验的26.9.9 core；它们不是额外的生产运行依赖。在 Linux 包目录中：

```bash
python3 tests/check.py
export SFXH_TEST_CORE=/absolute/path/to/verified/xray
bash tests/unit.sh
bash tests/transactions.sh
bash tests/ui.sh
python3 tests/protocol_lab.py --core "$SFXH_TEST_CORE" --jq /usr/bin/jq --openssl /usr/bin/openssl --curl /usr/bin/curl
shellcheck --severity=warning --exclude=SC2034,SC1091 sf-xray-hop sfxh install.sh lib/*.sh tests/*.sh
```

测试生成的凭据和详细临时记录只保存在 `.cache/`，该目录不进入源码发行包。Windows 使用 Git Bash；原生 jq 需要 `-b` 输出 LF，可用开发目录的包装器。Windows 不能代替 Linux 部署验收。

## VPS 分阶段验收

仅在用户明确指定的干净测试 VPS 上执行安装、更新、卸载和故障注入。每台分别记录 `/etc/os-release`、核心版本、客户端版本、时间和结果。

1. 通过 `install --version 26.9.9 --rtt 0` 安装；确认端口、服务用户、文件权限。另一次用1-RTT重复。
2. `sudo bash tests/vps-acceptance.sh /root/sfxh-result.json` 生成只读检查记录；它执行 unit 校验、权限、启用状态与 doctor，不重启、不更新、不卸载。
3. 实际执行停启／restart并复测，再重启 VPS 验证开机恢复。检查现有安装、缺依赖、APT 锁、坏软件源和端口占用的处理。
4. 在三种出口系统逐一创建节点；每种入口系统导入每种出口，完成9组配对。独立设备记录入口 Direct 和 Relay 的实际出口，并与各 VPS 的基准出口比较。
5. 保存入口两条 URI到0600文件。替换B2成功后比较连接参数（允许备注反映新出口），入口认证材料应不变；候选错误或测试失败时原B仍可访问。关闭B时 Relay失败，Direct仍可用；明确remove后Relay恢复入口出口。
6. 验证 core 更新成功、候选失败自动恢复、手动rollback保留当前下游。分别在候选测试、切换、正式复测阶段注入终止；每台OS独立测试断电／开机恢复，不在生产节点做故障注入。
7. 从出口和入口各走一次向导，测试非法数字、超长链接、空回车、无色窄终端、SSH断开续接及已完成向导重新进入。确认日志没有凭据，测试结束没有额外公网监听或残留探测。
8. 用独立手机／电脑测试长URI和客户端JSON；记录实际客户端与core版本。在指定1C1G／200Mbps节点按需测速，记录上限、实际吞吐、资源峰值与测试端点，不外推其他硬件。
9. 测试显式 --keep-data 卸载后恢复原身份，以及默认完整卸载后重新安装；共享系统依赖、防火墙、DNS和SSH配置应保持正常。

## 源码发行包

`python3 tools/package.py` 从显式文件白名单创建 `artifacts/SF-Xray-Hop-<管理程序版本>.tar.gz` 和相邻SHA256文件；自动检查LF、固定Unix脚本权限，排除 `.cache/` 和测试凭据。当前候选版本0.2.5。正式发布清单使用 `python3 tools/package.py --release-commit <完整HEAD>`，必须为干净且匹配的提交。`python3 tests/package.py` 再核对摘要、逐文件字节、路径、权限及运行依赖。打包成功不等于完成全部平台验收。本地发行包摘要与 GitHub 固定提交 tar.gz 摘要不是同一个值，不可混用。

## 一键安装入口验收

Linux上以root运行 `python3 tests/bootstrap.py`，仅操作临时测试目录；网络下载与管理程序使用隔离替身，不安装服务。覆盖管道入口、SSH终端输入、下载失败、损坏压缩包、路径穿越、符号链接、退出状态、临时文件清理和离线入口。`tests/ui.sh` 另外覆盖首次安装完成、已有安装直接管理、取消不报成功；不能用这些测试代替真实重装验收。

2026-09-30 的 v0.1.3 阶段：Ubuntu22.04与Ubuntu24.04各通过10项bootstrap检查；本地通过12项菜单流程检查、ShellCheck及源码／文档检查。当时将两台VPS留为空安装状态，供用户自行部署；用户随后重新安装，不能将该历史清理状态当作当前状态。

## v0.1.4 审查修复回归（2026-09-30）

保持现有两台正式 xray.service 运行，在单独 `/tmp` 源码目录生成测试根与凭据。Ubuntu22.04（systemd249、jq1.6）及Ubuntu24.04.3（systemd255、jq1.7）分别执行以下检查，core 为官方26.9.9 Linux amd64；测试不修改正式配置、不更新核心、不重启正式服务。

| 检查 | 两台各自结果 | 验证范围 |
|---|---|---|
| archive.sh | 7项通过 | 归档阶段SIGKILL、损坏恢复、引用保护、并发发布；没有断电 |
| transactions.sh | 19项通过 | Linux实际锁／代次切换，服务与网络替身；含元数据无重启、停止服务恢复、离线失败恢复 |
| prune.sh | 5项通过 | 保护活动／恢复引用，至少5个验证核心，旧孤立目录清理 |
| bootstrap.py | 15项通过 | 下载／管理器替身、PTY、固定版本、摘要与版本拒绝、离线入口 |
| manager.sh | 5项通过 | 隔离安装树的原子代码升级；未升级正式安装 |
| exits.sh | 5项通过 | 样本可比性与完整health调度在HTTPS成功但Relay出口错误时拒绝 |
| reporting.sh | 8项通过 | 合成传输／CPU样本、错误端点拒绝、磁盘不足；没有压力测速 |
| unit.sh / ui.sh | 32 / 13项通过 | 实际core配置与URI，数字菜单业务替身，重复安装使用已安装管理器 |
| probe-privileges.sh | 3项通过 | 实际DynamicUser、CapEff为0、凭据权限、停止／到期清理 |
| health-live.sh | 3项通过 | 默认target、真实降权core、HTTPS、独立下游基准及回环双跳比对 |

`health-live.sh` 的两跳在**每台机器内部**完成，公网出口相同；它验证新检测实现能工作，不证明新版不同 VPS 的路由或真实 B2 替换。本轮没有使用正式节点密钥做客户端测试。测试前后正式服务 PID 与启动时间保持一致，临时单元结束后无残留。

Windows 同时重新运行官方26.9.9的 `protocol_lab.py`，26项真实进程检查通过（0/1-RTT、两种身份、故障关闭、替换／取消、旧客户端参数）。源码检查覆盖27个Bash文件、LF、文档链接／命令及敏感信息；ShellCheck warning级通过。新增测速分类在jq1.6和1.7分别复测，1KiB端点格式核对不计为容量测试。

新增Linux检查可在隔离源码目录按需复现：

```bash
export SFXH_TEST_CORE=/absolute/path/to/verified/xray
bash tests/archive.sh
bash tests/exits.sh
bash tests/prune.sh
bash tests/reporting.sh
bash tests/manager.sh
python3 tests/bootstrap.py
# 以下需要root及可操作的systemd；仅临时回环单元，后一个会发送少量HTTPS请求。
bash tests/probe-privileges.sh
bash tests/health-live.sh
```

新版全新安装／管理器升级的正式服务验收、Debian矩阵、真正断电、不同出口双机、手机GUI和持续容量测试仍待完成；见[审查处理边界](audit-0.1.3.md)。

发布入口另行核对：源码提交 `bfa4edabf04afeda7345d61ba6a74e063122d578` 的 GitHub tar.gz SHA256 为 `459218e275d47ab2bbf5a0bacbd1196bbcd5a5a2339ae1b08b3823e75643c3a2`；公开 bootstrap 字节与该源码一致。两台Ubuntu均实际下载、校验并进入该管理器，然后用刻意缺值的参数在安装前退出，正式服务PID与启动时间未变。这证明公开下载入口可用，不计作重装或升级通过。

## v0.2.0 R2 实现回归（2026-09-30）

以下是实际部署前的隔离回归记录。之后获准改动两台VPS，部署、故障注入、升级与外部客户端的新增证据见[R2实机记录](vps-r2-2026-09-30.md)，不覆盖或冒用下面的历史结果。

依据用户提供的[R2需求快照](requirements-r2.md)实施。两台已有节点的正式服务持续运行；本轮只在 `/tmp/sfxh-r2-20260930/` 的私有测试根生成夹具及凭据。Ubuntu22.04使用jq1.6、systemd249；Ubuntu24.04.3使用jq1.7、systemd255。真实核心均为已核验的26.9.9 Linux amd64。以下每项均分别在两台完成，夹具测试不是全新安装或跨机器双跳验收。

| 检查 | 每台结果 | 边界 |
|---|---|---|
| unit.sh | 32通过 | 真实生成器、核心配置验证、URI语义回环及拒绝非法输入 |
| product-r2.sh | 13通过 | 名称安全、角色与分享、独立RTT、旧状态迁移；HTTP为夹具 |
| install-r2.sh | 3通过 | 默认无协议问答、只显示Direct、非TTY不泄露、重复安装保留；部署为夹具 |
| core-r2.sh | 5通过 | 数值升降级、同标签内容变化确认、pinned；下载／提交为夹具 |
| transactions.sh | 21通过 | 中断、恢复、metadata不重启／不启动、离线边界；服务和网络为夹具 |
| ui.sh | 13通过 | 数字交互、取消、续接、异常参数、已有安装委托；业务动作模拟 |
| archive.sh | 7通过 | 归档中断／并发发布和引用保护 |
| exits.sh | 5通过 | 比较口径和错误出口拒绝；网络为夹具 |
| prune.sh | 5通过 | 恢复引用及历史保留边界 |
| reporting.sh | 8通过 | 部分流量、错误响应、资源统计和空间边界 |
| manager.sh | 5通过 | 完整目录切换、旧布局保存、兼容拒绝；正式服务不操作 |
| self-update.sh | 10通过 | 清单／标签／摘要、脚本回退、中断与后置失败恢复双指针、共享锁、完整卸载；HTTPS和systemd为夹具 |
| bootstrap.py | 20通过 | 管道PTY、固定源码、正式／实验发行过滤、缺少Release、摘要及归档拒绝；下载及安装为夹具 |
| probe-privileges.sh | 3通过 | 真实临时systemd单元，非root UID、空capabilities、私有凭据、停止及超时 |
| health-live.sh | 3通过 | 真实TLS目标、HTTPS、独立基准与回环链式比较；共用公网出口，不是两台路由证明 |

Windows官方26.9.9核心回环实验26项通过：两种RTT、两种身份、替换及取消下游、下游故障不直出、旧客户端材料继续有效。R2允许备注反映新出口，测试比较连接参数而非备注的字节一致性。

`tests/check.py` 通过Bash语法、LF、相对链接、命令文档、敏感信息检查；ShellCheck以warning级别通过（排除模块间共享变量的SC2034），`git diff --check`通过。发行包只取白名单，不包含.cache、测试密钥或原始日志。

本轮核对正式服务前后状态均为active，PID与ActiveEnterTimestampMonotonic不变。以上不代表R2已在正式节点升级验收。正式发行仍待Debian12/13、3×3跨系统、真实全新安装／升级／卸载、独立GUI客户端、整机重启／断电及外部200Mbps稳定性验证。
