# Yuan Panel（原 HY2 一键管理工具）

VPS 多协议节点一键部署与管理面板：Hysteria2、VLESS+REALITY、Trojan、Shadowsocks，一个命令全搞定。

[English](README_EN.md) · [协议说明](docs/protocols.md) · [安全说明](docs/security.md) · [FAQ](docs/faq.md)

## 功能

- **多协议**：Hysteria2 / VLESS+REALITY / Trojan / Shadowsocks-2022，可共存
- **状态仪表盘**：打开面板一眼看到各协议运行状态
- **安全默认**：高强度随机密码、密码不回显、配置文件 600 权限、umask 077
- **防火墙**：部署自动放行端口，一键收紧仅留 SSH + 协议端口
- **系统调优**：BBR（FQ/CAKE）、通用内核参数优化
- **安全检查**：一键审计 SSH、权限、防火墙，给出整改建议
- **自更新**：面板内检查更新，git 增量升级

## 快速开始

```bash
bash <(curl -sL https://raw.githubusercontent.com/yuan1228/hy2/refs/heads/main/install.sh)
```

安装完成后，随时输入 `yuan` 进入面板。

## 菜单一览

```
============================================================
  Yuan Panel v2.0.0 · 多协议节点管理
------------------------------------------------------------
  ● Hysteria2      运行中 :48443
  ○ VLESS+REALITY  未安装
  ○ Trojan         未安装
  ○ Shadowsocks    未安装
============================================================

  协议管理：
   1. Hysteria2
   2. VLESS+REALITY
   3. Trojan
   4. Shadowsocks

  系统工具：
   5. 网络调优 (BBR)
   6. 防火墙管理
   7. 安全检查
   8. 查看全部节点链接
   9. 检查更新
   0. 退出
```

每个协议有独立子菜单：安装/重装、查看链接、状态、重启、日志、卸载。

## 项目结构

```
├── install.sh              # 安装引导（一键安装/更新面板）
├── yuan                    # 入口命令
├── version.txt             # 版本号
├── src/
│   ├── common.sh           # 公共库（颜色/系统检测/密码/网络）
│   ├── menu.sh             # 主菜单与仪表盘
│   ├── update.sh           # 自更新
│   ├── protocols/          # 协议模块
│   │   ├── hysteria2.sh
│   │   ├── vless.sh        # VLESS+REALITY（Xray）
│   │   ├── trojan.sh       # Trojan（Xray）
│   │   ├── shadowsocks.sh  # SS 2022（rust）
│   │   └── _xray.sh        # Xray 共享助手（内部）
│   └── system/             # 系统模块
│       ├── tuning.sh       # BBR/内核调优
│       ├── firewall.sh     # 防火墙（nftables/iptables）
│       └── security.sh     # 安全检查
└── docs/                   # 文档
```

加新协议只需在 `src/protocols/` 新增模块并实现 8 个标准函数
（`installed/active/port/deploy/link/restart/logs/uninstall/status`），
再在 `src/menu.sh` 的 `PROTOS` 数组里注册一行即可。

## 注意事项

- 需要 root 权限
- Hysteria2 使用 UDP，请确认云厂商安全组放行 UDP
- VLESS REALITY 伪装目标请用小证书站点（默认 www.cloudflare.com），
  大证书站点（如 www.microsoft.com）会导致握手失败
- Shadowsocks 2022 需要新版客户端

## 许可证

MIT，详见 [LICENSE](LICENSE)。
