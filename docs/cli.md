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

安装默认443、0-RTT、Chrome、XHTTP auto、archive.archlinux.org、pre；名称为内部稳定 ID 派生的 `node-短ID`。只在端口冲突、地址未知或验证失败等异常时提问。重复安装不重设现有频道。顶层 `--version` 显示脚本版本，install/core 的 `--version` 指核心；安装器 `--script-version` 指项目发行版，两者独立。

主菜单6进入的核心子菜单1和 `core update` 总是查询并应用官方最新核心（正式版 / Pre 取较大版本），即使之前自主选择了版本、恢复了历史核心或显式使用过 stable。`core check` 同样查看最新核心（正式版 / Pre 取较大版本），但不切换版本。核心子菜单2直接输入版本号，对应 `core select 26.9.9`；可写 `v26.9.9`，也兼容 `core update --version 26.9.9` 和在线 `core rollback 26.9.9`。指定版本会记为 pinned，普通启动或重复安装保持该选择；下一次默认更新重新比较正式版与 Pre。这里的自动拉取发生于安装／更新命令，没有后台定时换核。

安装、在线选择和本地历史恢复的最低核心均为 **26.9.9**，低于下限时 `--yes` 也不能放行。在线选择不要求本地曾安装过该版本，但官方必须存在对应 Release，且通过摘要、能力、安全及连接检查；未知版本或不兼容版本不会切换。核心子菜单3恢复上一可用核心；核心子菜单4选择本地已验证历史；显式选择正式版继续使用 `core update --channel stable`。`core rollback --offline` 仅接受本地历史选择或完整归档 ID。

`view` 和 `view json` 默认 Direct。`relay` 只面向入口设备，`handoff` 只在明确设为出口后提供。JSON 的本地 HTTP 端口为127.0.0.1:10809，不含服务端私钥。提示写 stderr，导出写 stdout。名字是备注而非凭据；修改后旧客户端的备注不会自动同步。

JSON 是完整 Xray 客户端配置。GUI 的“自定义配置”可能直接采用其中的监听端口；例如现有 v2rayN 使用 10808 时，不能假定导入 10809 的 JSON 后应用代理端口自动匹配。测试时先核对本地端口和代理类型；导出的是 HTTP 入站，不应填入要求后端 SOCKS 的选项。普通使用优先导入已验证的长 URI，自定义 JSON 的 GUI 验收范围见[客户端记录](vps-lifecycle-0.2.5-2026-10-01.md)。

```bash
sudo sh -c 'umask 077; sfxh view json direct > /root/direct-client.json'
sudo sfxh chain set < /root/exit-handoff.uri
```

链接只从隐藏终端输入或 stdin 读取，不放在 argv 或 shell 历史；文件由管理员保存为0600。取消链式或入口改为其他用途会改变 Relay 出口，非交互必须 `--yes`。直接指定受支持版本已表达切换意图，选择较低版本不再额外要求降级确认；频道解析出的最新版本低于当前版本，以及同标签内容改变，仍需确认／`--yes`。脚本更新与回滚同样有明确确认。

退出码：0成功，1验证／执行失败，2用法错误，130取消／中断；中断脚本事务恢复返回75，提示重开命令加载恢复后的代码。工具错误可能透传其非零码。`core rollback --offline` 仍要求历史核心通过当前隔离安全检查及本地启动，不报告公网成功。

完整卸载默认删除私密数据，交互输入 `UNINSTALL`；空回车、EOF、其他文字不删除。`--keep-data` 是显式保留选项；旧 `--purge` 作为完整卸载兼容别名。
