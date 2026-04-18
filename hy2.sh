#!/bin/bash

# ====================================================
# 修正版 Hysteria2 官方规范部署脚本 (修复 YAML 解析 Bug)
# ====================================================

PORT=45678
PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
OBFS_PASSWORD=$(tr -dc a-z0-9 </dev/urandom | head -c 8)
SNI="aws.amazon.com"

IP=$(curl -4s -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")
if [ -z "$IP" ]; then
    IP=$(curl -6s -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")
fi

echo -e "\e[33m>>> 1. 执行官方标准安装...\e[0m"
bash <(curl -fsSL https://get.hy2.sh/)

echo -e "\e[33m>>> 2. 生成 ECDSA 证书...\e[0m"
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout /etc/hysteria/server.key \
    -out /etc/hysteria/server.crt \
    -subj "/CN=$SNI" -days 36500 2>/dev/null

PIN_SHA256=$(openssl x509 -in /etc/hysteria/server.crt -outform DER | sha256sum | awk '{print $1}')

echo -e "\e[33m>>> 3. 写入配置 (已修复 obfs 的层级嵌套 Bug)...\e[0m"
cat <<EOF > /etc/hysteria/config.yaml
listen: :$PORT

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: $PASSWORD

obfs:
  type: salamander
  salamander:
    password: $OBFS_PASSWORD

masquerade:
  type: proxy
  proxy:
    url: https://$SNI
    rewriteHost: true

ignoreClientBandwidth: true
EOF

echo -e "\e[33m>>> 4. 权限下放给 hysteria 官方低权限账户...\e[0m"
chown -R hysteria:hysteria /etc/hysteria/

echo -e "\e[33m>>> 5. 启动守护进程...\e[0m"
systemctl daemon-reload
systemctl enable hysteria-server.service >/dev/null 2>&1
systemctl restart hysteria-server.service

sleep 2 
SERVICE_STATUS=$(systemctl is-active hysteria-server)

if [ "$SERVICE_STATUS" = "active" ]; then
    echo -e "\e[32m[OK] Hysteria2 服务已成功启动！YAML 解析完美通过。\e[0m"
else
    echo -e "\e[31m[ERROR] 服务启动失败！请运行 'journalctl -u hysteria-server -e' 查看日志。\e[0m"
    exit 1
fi

echo -e "\n\e[36m======================================================\e[0m"
URI="hysteria2://$PASSWORD@$IP:$PORT/?sni=$SNI&obfs=salamander&obfs-password=$OBFS_PASSWORD&pinSHA256=$PIN_SHA256#Hy2-Fixed"
echo -e "\e[32m$URI\e[0m"
echo -e "\e[36m======================================================\e[0m"
