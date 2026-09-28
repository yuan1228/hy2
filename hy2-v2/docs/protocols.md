# 协议说明与客户端配置

Yuan Panel v2.0.0 内置四种协议，可共存部署。选择建议：

| 协议 | 传输 | 特点 | 适合场景 |
|------|------|------|----------|
| Hysteria2 | UDP | QUIC，弱网/高丢包下速度最快 | 主力日常使用 |
| VLESS + REALITY | TCP 443 | TLS 指纹伪装，无需域名证书 | 抗封锁、备用 |
| Trojan | TCP | 经典伪装协议，兼容性好 | 备用、老客户端 |
| Shadowsocks 2022 | TCP+UDP | 轻量，几乎所有客户端都支持 | 兜底、IoT/路由器 |

## Hysteria2

- 认证：密码；混淆：salamander；伪装：HTTPS 回源
- 客户端需开启「跳过证书验证」（自签证书）
- 分享链接形如 `hysteria2://…?insecure=1&sni=…&obfs=salamander&…`

客户端：Shadowrocket、Streisand、NekoBox、Hiddify、v2rayNG（需插件）

## VLESS + REALITY

- Xray 核心，`xtls-rprx-vision` 流控
- 伪装目标默认 `www.cloudflare.com`；**不要使用证书链超大的站点**
  （如 `www.microsoft.com`，其证书 > 8192 字节会导致 xray REALITY 握手失败）
- 分享链接包含 `pbk`（公钥）、`sid`、`fp=chrome` 等参数，复制时请复制完整

客户端：Shadowrocket、Streisand、NekoBox、Hiddify、v2rayNG、V2RayXS

> 若客户端提示 REALITY 握手失败：先确认链接复制完整，再检查服务端时间是否准确
> （`timedatectl`，时间偏差过大会导致 TLS 失败）。

## Trojan

- Xray 核心，自签证书
- 客户端需开启「跳过证书验证」（allowInsecure）

## Shadowsocks 2022

- 加密方式固定为 `2022-blake3-aes-128-gcm`
- 注意：部分老客户端不支持 2022 系列加密，请使用新版客户端
  （Shadowrocket、Streisand、NekoBox 均支持）

## 端口规划建议

- VLESS + REALITY：443（最不易被封）
- Trojan：4443 或其他高位端口（避免与 VLESS 冲突）
- Hysteria2：40000–50000 随机 UDP 端口
- Shadowsocks：8388 或其他高位端口

面板在部署时会自动检测端口占用，重复部署同一协议会提示覆盖。
