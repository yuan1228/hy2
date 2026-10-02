# Alpine (OpenRC) 支持 · 变更说明

本次改动让工具箱在 Alpine Linux (OpenRC) 上完整可用，同时保持 Debian/Ubuntu (systemd) 行为不变。

## 核心：init 系统抽象层（src/common.sh）

- 新增 `detect_init()`：通过 `/run/systemd/system` 和 `rc-service` 自动识别 systemd / OpenRC
- 新增 `svc_name()`：服务名标准化，去掉 `.service` 后缀（OpenRC 不用后缀）
- `svc_active` / `svc_enabled` / `svc_restart` / `svc_stop`：全部改为双 init 兼容
  - OpenRC 下用 `rc-service <name> status/restart/stop`，自启检查读 `rc-update show default`
- 新增 `svc_install <name.service> <描述> <可执行文件> <参数> [日志文件]`：
  - systemd：写 `/etc/systemd/system/*.service`
  - OpenRC：写 `/etc/init.d/*`（openrc-run 脚本，background 模式 + pidfile + 日志重定向到 `/var/log/<name>.log`），并 `rc-update add default`
- 新增 `svc_uninstall`：停止 → 取消自启 → 删除服务定义（双 init）
- 新增 `svc_logs` / `svc_logs_follow`：systemd 走 journalctl，OpenRC 走 `tail /var/log/<name>.log`
- `port_used()`：Alpine 精简版无 `ss` 时回退到 busybox `netstat`
- 新增 `show_listening()`：同上，供"当前监听端口"展示用

## Hysteria2（src/protocols/hysteria2.sh）

- 新增 `hy2_ensure_bin()`：systemd 下仍走官方 `get.hy2.sh`；Alpine/OpenRC 下改为从 GitHub releases 直接下载二进制（官方脚本强制要求 systemd，且用了 busybox 不支持的 `grep -P`）
- 部署 step 5 改为 `svc_install` + `svc_restart`
- `hy2_logs` / `hy2_uninstall` 改为 `svc_*` 抽象
- **修 bug**：`ensure_cmd openssl` 提前到 `gen_hex` 求值之前（之前 openssl 缺失会直接 die，就是之前看到的两条"缺少依赖命令"）

## Xray 系（_xray.sh / vless.sh / trojan.sh）

- `xray_deploy_service()` 改为 `svc_install`（删掉手写 systemd unit）
- `vless_logs` / `trojan_logs` → `svc_logs` + `svc_logs_follow`
- `vless_uninstall` / `trojan_uninstall` → `svc_uninstall`
- **修 bug**：`xray_shortid()` 补上 `ensure_cmd openssl`（之前缺失时静默返回空 shortid）
- **修 bug**：trojan 部署提前 `ensure_cmd openssl`（gen_hex 在 ask 默认值里求值）

## Shadowsocks（src/protocols/shadowsocks.sh）

- 手写 systemd unit 改为 `svc_install`
- `ss_logs` / `ss_uninstall` → `svc_*` 抽象
- **修 bug**：部署提前 `ensure_cmd openssl`（gen_pass 在 ask 默认值里求值）

## 系统模块

- `src/system/security.sh`：fail2ban 检查改为 `svc_active fail2ban`（双 init）；监听端口展示用 `show_listening()`
- `src/system/maintenance.sh`：journal 清理只在 systemd 下执行；OpenRC 下改为清理 7 天前的 `/var/log/*.log`
- `src/system/firewall.sh`：监听端口展示用 `show_listening()`

## 升级方式

直接覆盖全部文件后，在 VPS 上重新拉取即可。已部署的 systemd 服务不受影响；
Alpine 上重新跑一遍"安装/重新部署"会自动走 OpenRC 路径。

## 已知限制

- OpenRC 下的日志是文本文件（`/var/log/<服务名>.log`），没有 journalctl 的按时间过滤，`svc_logs` 只支持 tail 行数
- `svc_enabled` 在 OpenRC 下只检查 `default` 运行级别
