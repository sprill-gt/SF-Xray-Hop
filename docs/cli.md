# 命令与数字菜单

核心版本选择及默认追最新核心（正式版 / Pre 取较大版本）的新语义适用于 0.2.7 RC。

`sf-xray-hop` 与 `sfxh` 等价，管理操作使用 root／sudo。无参数进入中文数字菜单；顶部明确显示“脚本版本”，与下方运行／配置核心版本分开。主菜单空回车退出，子菜单0返回。无效数字留在当前步骤。非交互命令不等待菜单输入。

`sfxh version` 查看当前加载的管理脚本版本，无需 sudo、jq、安装节点或联网；`sfxh --version` 保持仅输出数字版本号，供自动化读取。更新菜单也显示当前脚本版本。两者都不会发起更新或重启服务。

| 菜单 | 用途 |
|---|---|
| 1 | 配置链式；已有入口时提示进入管理，不重新配置 |
| 2 | 管理链式；检查、更换或取消出口，未配置时只提示 |
| 3 | 分享链接，按本机角色显示直连、链式或出口对接链接 |
| 4 | 节点设置：名称、用途和登记入口 |
| 5 | 连接设置：SNI、RTT |
| 6 | Xray 核心：更新最新、指定版本号、恢复上一版本、本地历史 |
| 7 | 检测与日志 |
| 8 | 更新管理脚本、恢复上一脚本 |
| 9 | 卸载，需确认词 |
| 0 | 退出 |

0.2.9 的状态栏仅显示节点、地址/系统、运行核心、连接参数及链式状态。不显示源码提交、历史检测、内存或路径解释。交互终端使用青色标题/序号、绿色运行和红色停止状态；`NO_COLOR=1 sfxh` 或重定向时输出纯文本。主菜单0或空回车退出，子菜单0返回。

```text
sfxh version
sfxh --version
sfxh install [--address 地址] [--port 443] [--rtt 0|1]
             [--target auto|域名] [--name 名称]
             [--channel pre|stable] [--version 核心版本]
sfxh guide
sfxh view [direct|relay|handoff]
sfxh view json [direct|relay]
sfxh node name 名称
sfxh node downstream-name 名称
sfxh node role standalone|exit [--yes]
sfxh node entry 地址 [名称]
sfxh node entry clear
sfxh status
sfxh doctor
sfxh test [--performance [--profile direct|relay]]
sfxh chain set|replace|test
sfxh chain remove [--yes]
sfxh rtt [0|1]
sfxh rtt downstream 0|1
sfxh target [auto|set 域名]
sfxh fingerprint chrome|firefox|safari
sfxh core check
sfxh core update [--channel auto|pre|stable|pinned] [--version 版本] [--yes]
sfxh core select 版本号 [--yes]
sfxh core 版本号 [--yes]
sfxh core rollback [版本号|完整归档ID|--previous] [--offline]
sfxh core prune
sfxh self check [--version 版本 --allow-pre]
sfxh self update [--version 版本 --allow-pre] [--yes]
sfxh self rollback [--yes]
sfxh logs
sfxh uninstall [--yes] [--keep-data]
```

安装默认443、0-RTT、Chrome、XHTTP auto、archive.archlinux.org、最新（含 Pre）；名称为内部稳定 ID 派生的 `node-短ID`。只在端口冲突、地址未知或验证失败等异常时提问。重复安装不重设现有频道。顶层 `--version` 显示脚本版本，install/core 的 `--version` 指核心；安装器 `--script-version` 指项目发行版，两者独立。

主菜单6的核心子菜单1和 `core update` 按保存的 track 选择版本；旧状态和新装默认 latest（正式版与 Pre 按数字比较），子菜单5可切换 stable。`core check` 按同一设置查看并提供最新正式版对照，不切换核心。子菜单2或 `core select 版本号` 固定版本，后续更新解除固定并按 track 选择。这里的自动拉取只发生于安装／更新命令，没有后台定时换核。

安装、在线选择和本地历史恢复的最低核心均为 **26.9.9**，低于下限时 `--yes` 也不能放行。在线选择不要求本地曾安装过该版本，但官方必须存在对应 Release，且通过摘要、能力、安全及连接检查；未知版本或不兼容版本不会切换。核心子菜单3恢复上一可用核心；核心子菜单4选择本地已验证历史；显式选择正式版继续使用 `core update --channel stable`。`core rollback --offline` 仅接受本地历史选择或完整归档 ID。

`view` 和 `view json` 默认 Direct。`relay` 只面向入口设备，`handoff` 只在明确设为出口后提供。JSON 的本地 HTTP 端口为127.0.0.1:10809，不含服务端私钥。提示写 stderr，导出写 stdout。名字是备注而非凭据；修改后旧客户端的备注不会自动同步。

JSON 是完整 Xray 客户端配置。GUI 的“自定义配置”可能直接采用其中的监听端口；例如现有 v2rayN 使用 10808 时，不能假定导入 10809 的 JSON 后应用代理端口自动匹配。测试时先核对本地端口和代理类型；本版同时提供 HTTP 10809 和 SOCKS5 10808（UDP 开启、UDP/443 本地阻断），需核对 GUI 端口是否冲突。普通使用优先导入已验证的长 URI，自定义 JSON 的 GUI 验收范围见[客户端记录](archive/vps-lifecycle-0.2.5-2026-10-01.md)。

```bash
sudo sh -c 'umask 077; sfxh view json direct > /root/direct-client.json'
sudo sfxh chain set < /root/exit-handoff.uri
```

链接只从隐藏终端输入或 stdin 读取，不放在 argv 或 shell 历史；文件由管理员保存为0600。取消链式或入口改为其他用途会改变 Relay 出口，非交互必须 `--yes`。直接指定受支持版本已表达切换意图，选择较低版本不再额外要求降级确认；频道解析出的最新版本低于当前版本，以及同标签内容改变，仍需确认／`--yes`。脚本更新与回滚同样有明确确认。

退出码：0成功，1验证／执行失败，2用法错误，130取消／中断；中断脚本事务恢复返回75，提示重开命令加载恢复后的代码。工具错误可能透传其非零码。`core rollback --offline` 仍要求历史核心通过当前隔离安全检查及本地启动，不报告公网成功。

完整卸载默认删除私密数据，交互输入 `UNINSTALL`；空回车、EOF、其他文字不删除。`--keep-data` 是显式保留选项；旧 `--purge` 作为完整卸载兼容别名。

客户端 JSON 导出包含回环 HTTP `10809` 与 SOCKS5 `10808`（支持 UDP）；内部健康检测不占用这两个固定端口。GitHub API 可通过环境变量 `SFXH_GITHUB_TOKEN`（优先）或 `GITHUB_TOKEN` 认证；令牌不用于发行资产下载。

## 核心更新跟随与撤回版本

`sfxh core track` 查看更新跟随；`sfxh core track latest` 保存最新（含 Pre），`sfxh core track stable` 保存仅正式版。只修改元数据，不换核、不重启服务；下次 `sfxh core update` 才按新设置选择。`core.channel` 仍记录当前版本来源；缺少 `core.track` 一律按 latest。

`sfxh install --core-track stable` 可在新装时选择仅正式版。旧的 `--channel auto|pre|stable` 继续兼容；更新时显式 `--channel` 只影响本次操作，不改保存的 track。`--version` 固定当前核心，后续默认更新仍按 track 选择并解除固定。菜单 6 的第 5 项可切换更新跟随。

撤回版本清单位于 `data/core-denylist.json`；26.10.29 已被上游撤回。自动选择跳过撤回版本，指定版本和恢复也拒绝选择它；doctor/core check 对正在运行的撤回版本只警告，不自动换核。

## 可选 BBR

`sfxh tune bbr status` 查看；`sfxh tune bbr on` 显式开启 BBR + fq；`sfxh tune bbr off` 恢复原值。菜单 5 → 3 提供同样的选项。新装可选 `--bbr on`，默认 off，已有安装重复运行 install 不会接管 BBR。

仅使用当前内核提供的 BBR；不下载第三方脚本、不替换内核、不重启。内核版本至少 4.9，模块不可用、缺少权限或共享内核容器会停止。开启前记录两个 sysctl 原值，使用本项目独立的 sysctl.d 和 modules-load.d 文件；卸载先恢复。外部编辑或其他工具修改了已接管值时停止恢复并保留记录，需人工协调后重试。
