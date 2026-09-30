# 命令与数字菜单

`sf-xray-hop` 与 `sfxh` 等价，管理操作使用 root／sudo。无参数进入中文数字菜单；顶部明确显示“脚本版本”，与下方运行／配置核心版本分开。主菜单空回车退出，子菜单0返回。无效数字留在当前步骤。非交互命令不等待菜单输入。

`sfxh version` 查看当前加载的管理脚本版本，无需 sudo、jq、安装节点或联网；`sfxh --version` 保持仅输出数字版本号，供自动化读取。更新菜单也显示当前脚本版本。两者都不会发起更新或重启服务。

| 菜单 | 命令 | 用途 |
|---|---|---|
| 1 | `sfxh guide` | 开始／管理链式，更换、取消、排障 |
| 2 | `sfxh core` | 核心更新、pre/stable 切换、历史回滚／固定版本 |
| 3 | `sfxh view direct` | 本机直连链接 |
| 4 | `sfxh view relay` | 入口 A 的设备链式链接 |
| 5 | `sfxh node` | 名称、用途、关联机器信息 |
| 6 | `sfxh target` | SNI／REALITY 目标 |
| 7 | `sfxh rtt` | 本机与下游 RTT 分别设置 |
| 8 | `sfxh self` | 脚本更新与回滚 |
| 9 | `sfxh uninstall` | 完整卸载，需确认词 |
| 0 | — | 退出 |

`core`、`node`、`self` 命令需要下列子命令；表中短写表示业务入口。单机的菜单4提示尚未开启链式；出口 B 的菜单4解释在 A 获取设备链接并显示用户登记的 A 地址，不伪造 A 的凭据。

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
sfxh core update [--channel pre|stable|pinned] [--version 版本] [--yes]
sfxh core rollback [完整归档ID|--previous] [--offline]
sfxh core prune
sfxh self check [--version 版本 --allow-pre]
sfxh self update [--version 版本 --allow-pre] [--yes]
sfxh self rollback [--yes]
sfxh logs
sfxh uninstall [--yes] [--keep-data]
```

安装默认443、0-RTT、Chrome、XHTTP auto、archive.archlinux.org、pre；名称为内部稳定 ID 派生的 `node-短ID`。只在端口冲突、地址未知或验证失败等异常时提问。重复安装不重设现有频道。顶层 `--version` 显示脚本版本，install/core 的 `--version` 指核心；安装器 `--script-version` 指项目发行版，两者独立。

`view` 和 `view json` 默认 Direct。`relay` 只面向入口设备，`handoff` 只在明确设为出口后提供。JSON 的本地 HTTP 端口为127.0.0.1:10809，不含服务端私钥。提示写 stderr，导出写 stdout。名字是备注而非凭据；修改后旧客户端的备注不会自动同步。

JSON 是完整 Xray 客户端配置。GUI 的“自定义配置”可能直接采用其中的监听端口；例如现有 v2rayN 使用 10808 时，不能假定导入 10809 的 JSON 后应用代理端口自动匹配。测试时先核对本地端口和代理类型；导出的是 HTTP 入站，不应填入要求后端 SOCKS 的选项。普通使用优先导入已验证的长 URI，自定义 JSON 的 GUI 验收范围见[客户端记录](vps-lifecycle-0.2.5-2026-10-01.md)。

```bash
sudo sh -c 'umask 077; sfxh view json direct > /root/direct-client.json'
sudo sfxh chain set < /root/exit-handoff.uri
```

链接只从隐藏终端输入或 stdin 读取，不放在 argv 或 shell 历史；文件由管理员保存为0600。取消链式或入口改为其他用途会改变 Relay 出口，非交互必须 `--yes`。核心降级、同标签不同二进制也需确认／`--yes`。脚本更新与回滚同样有明确确认。

退出码：0成功，1验证／执行失败，2用法错误，130取消／中断；中断脚本事务恢复返回75，提示重开命令加载恢复后的代码。工具错误可能透传其非零码。`core rollback --offline` 仍要求历史核心通过当前隔离安全检查及本地启动，不报告公网成功。

完整卸载默认删除私密数据，交互输入 `UNINSTALL`；空回车、EOF、其他文字不删除。`--keep-data` 是显式保留选项；旧 `--purge` 作为完整卸载兼容别名。
