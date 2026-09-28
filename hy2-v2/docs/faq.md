# 常见问题

## 安装失败：`git clone` 超时

国内部分网络到 GitHub 不稳定。多试几次，或先给机器配代理：

```bash
export https_proxy=http://127.0.0.1:7890
bash <(curl -sL https://raw.githubusercontent.com/yuan1228/hy2/refs/heads/main/install.sh)
```

## 面板提示「请使用 root 用户运行」

必须用 root：`sudo -i` 后再运行，或 `sudo yuan`。

## Hysteria2 连不上

1. 确认服务端 `systemctl is-active hysteria-server` 为 active
2. 确认 UDP 端口已放行（云厂商安全组 + 面板防火墙都要看）
3. 客户端开启「跳过证书验证」
4. 运营商 UDP QoS：换端口或改用 VLESS 备用

## VLESS REALITY 握手失败

1. 链接必须复制完整（含 `pbk`/`sid` 参数）
2. 服务端时间准确：`timedatectl` 检查，偏差大则 `timedatectl set-ntp true`
3. 不要把伪装目标换成大证书站点（如 www.microsoft.com）

## Shadowsocks 2022 客户端不支持

升级客户端到最新版。2022 系列加密需要较新的核心，老版本不支持。

## 从 v1（单文件版）升级

直接运行安装命令即可。Hysteria2 的旧配置（`/etc/hysteria/share_link.txt`）
会被自动识别，覆盖安装时端口/密码/SNI 会作为默认值保留。

## 卸载面板本身

```bash
rm -rf /opt/yuan-panel /usr/local/bin/yuan
```

各协议请先在面板内逐个卸载（会清理 systemd 服务），再删面板目录。
