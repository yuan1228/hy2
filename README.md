# Yuan VPS 工具箱

VPS 常用工具合集：节点搭建、WARP、系统维护、网络测试，一个 `yuan` 命令全搞定。
不含建站，只做 VPS 玩家真正天天用的东西。

[English](README_EN.md) · [协议说明](docs/protocols.md) · [安全说明](docs/security.md) · [FAQ](docs/faq.md)

## 快速开始

```bash
bash <(curl -sL https://raw.githubusercontent.com/yuan1228/hy2/refs/heads/main/install.sh)
```

安装完成后，随时输入 `yuan` 进入工具箱。

## 菜单一览

```
============================================================
  Yuan VPS 工具箱 v3.0.0
  Debian 12 · x86_64 · KVM
------------------------------------------------------------
  ● Hysteria2      运行中 :48443
  ○ VLESS+REALITY  未安装
  ○ Trojan         未安装
  ○ Shadowsocks    未安装
============================================================

 节点搭建
  1. Hysteria2 管理          2. VLESS+REALITY 管理
  3. Trojan 管理             4. Shadowsocks 管理
  5. WARP 管理
------------------------------------------------------------
 系统工具
  6. 本机信息                7. 系统更新
  8. 系统清理                9. BBR / 网络调优
 10. 防火墙管理             11. 安全检查
 12. 常用组件安装           13. 全部节点链接
------------------------------------------------------------
 网络测试
 14. TcpQuality             15. NodeQuality
------------------------------------------------------------
 00. 检查更新                88. 退出
============================================================
```

## 功能

**节点搭建**
- Hysteria2 / VLESS+REALITY / Trojan / Shadowsocks-2022，可共存
- 每个协议独立子菜单：安装、链接、状态、重启、日志、卸载
- WARP 快捷管理（IPv4/IPv6/双栈一键安装）

**系统工具**
- 本机信息：CPU/内存/硬盘/IP/归属地一目了然
- 系统更新、系统清理一键搞定
- BBR（FQ/CAKE）、通用内核参数优化
- 防火墙（nftables/iptables）：自动放行 + 一键收紧
- 安全检查：一键审计 SSH、权限、防火墙

**网络测试**（每次运行前自动检查上游更新）
- TcpQuality：TCP 三网质量检测
- NodeQuality：综合体检（YABS + IP 质量 + 网络质量），沙箱无痕运行

**工程**
- 模块化结构，加新工具只需加一个文件
- 高强度随机密码、密码不回显、配置文件 600 权限
- MIT 开源，shellcheck CI

## 项目结构

```
├── install.sh / yuan      安装引导 / 入口命令
├── src/
│   ├── common.sh menu.sh update.sh
│   ├── protocols/         hy2 / vless / trojan / ss（+ _xray 共享）
│   ├── system/            info / maintenance / tuning / firewall / security / pkgs
│   └── net/               warp / speed / unlock / route
├── docs/                  协议说明 / 安全说明 / FAQ
└── .github/               Issue 模板 / shellcheck CI
```

## 注意事项

- 需要 root 权限
- Hysteria2 用 UDP，云厂商安全组记得放行
- VLESS REALITY 伪装目标用小证书站点（默认 www.cloudflare.com）
- 本项目由 hy2 单协议脚本演进而来，v1 老用户配置自动兼容

## 许可证

MIT，详见 [LICENSE](LICENSE)。
