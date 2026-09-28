# 更新日志

## v2.0.0 (2026-09-28)

完全重构：

- **多协议**：新增 VLESS+REALITY（Xray）、Trojan（Xray）、Shadowsocks 2022（rust），
  与 Hysteria2 共存，统一管理
- **新架构**：单文件拆分为模块化结构（`src/protocols/`、`src/system/`），
  加新协议只需实现 8 个标准函数并注册一行
- **状态仪表盘**：主菜单顶部实时显示各协议运行状态
- **安全增强**：
  - 密码默认 32 位 hex / 24 字节 base64，输入不回显
  - `umask 077` 全局生效，配置目录 700、配置文件与链接 600
  - 新增防火墙模块（nftables/iptables），部署自动放行、一键收紧
  - 新增安全检查，一键审计 SSH/权限/防火墙
- **安装方式**：`install.sh` 改为引导器，面板本体安装到 `/opt/yuan-panel`，
  git 增量更新；`yuan` 命令进入面板
- **文档**：新增协议说明、安全说明、FAQ；英文 README
- **工程规范**：MIT 许可证、Issue 模板、shellcheck CI

### 兼容性

- v1 的 Hysteria2 配置（`/etc/hysteria/share_link.txt`）会被自动识别，
  覆盖安装时端口/密码/SNI 作为默认值保留

## v1.x

- 单文件 `install.sh`，仅支持 Hysteria2
- 功能：部署、查看链接、BBR、日志、状态、重启、卸载
