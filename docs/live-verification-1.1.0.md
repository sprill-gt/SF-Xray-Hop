# 1.1.0 稳定发行与脚本通道实测

日期：2026-11-01（UTC+8）。使用节点C（Debian 12）原有安装和运行服务，全部更新从公开 GitHub Release 下载，不使用本地替换包。

## 发行验证

- stable：v1.1.0，提交 a404d39ab747730b4ad23a781c538db6e3374356。
- pre：v1.1.1，提交 2bab69bf27cd339855f34d8c7bc1880dfa65814b；testing 分支只调整版本和发行通道。
- 两个分支的完整 CI、两次 Release 工作流均通过；下载公开发行资产核对清单中的提交、包大小、SHA256 与安装入口摘要。
- 两个源码包分别使用 `gh attestation verify --repo sprill-gt/SF-Xray-Hop` 验证 GitHub Actions 构建来源证明，退出码均为 0。
- 两个 Release 均已发布，1.1.1 标记为 prerelease，GitHub Latest 为正式版 1.1.0。
- 实机只调用已验证稳定安装入口的版本解析函数，公开 API、manifest 和标签提交检查成功，解析结果为 1.1.0 正式版。未执行重复安装。未来更高正式版的固定入口行为由 CI 引导回归覆盖。

## 实机切换

| 顺序 | 操作 | 实际结果 |
|---|---|---|
| 1 | 旧 0.2.10：`sfxh self update --version 1.1.1 --allow-pre --yes` | 1.1.1 / pre |
| 2 | `sfxh self update --yes` | 跟随当前 pre，仍为 1.1.1 |
| 3 | `sfxh self update --channel stable --yes` | 降到 1.1.0 / stable |
| 4 | `sfxh self update --channel pre --yes` | 升到 1.1.1 / pre |
| 5 | `sfxh self update --channel stable --yes` | 回到 1.1.0 / stable |
| 6 | `sfxh self update --yes` | 跟随当前 stable，仍为 1.1.0 |

每一步均逐字节比较完整节点状态、核心配置及服务单元，并检查服务 MainPID 与 active 状态：全部不变。核心保持原有 26.10.31，脚本通道独立于核心 track。最终保留 1.1.0 稳定版。

使用切换前的节点状态生成 Direct、Relay 两套旧身份配置，在独立 Windows 客户端各完成 4 次 HTTPS 请求，合计 8 次成功，出口均符合预期。私密配置、服务器地址和原始结果仅留在受限测试目录，不进入仓库或发行资产。

失败切换保留旧脚本和通道的验证来自隔离事务回归，未在生产节点故意破坏发行包。本次未重复验证系统安装、重启持久化或跨版本核心回退。

## 隐私历史处理

已重写可写公开分支和旧版本标签中的个人提交邮箱、厂商名称及 SSH 别名，并按新标签提交重建旧 RC 源码包与清单。提交及标签身份统一使用 GitHub noreply；标签保护规则已恢复为 active，禁止更新和删除 v* 标签。

GitHub 的旧 PR 引用、缓存、已下载的文件及他人克隆不受此次 Git 分支/标签重写控制，不能宣称这些副本也已删除。
