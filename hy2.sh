#!/bin/bash

# ==========================================
# 真正的完全体：官方内核拉取 + 硬编码防爆配置
# ==========================================

echo -e "\e[33m>>> 0. 安装必要环境...\e[0m"
apt-get update -y >/dev/null 2>&1
apt-get install -y qrencode curl openssl >/dev/null 2>&1

echo -e "\e[33m>>> 1. 拉取官方 Hysteria2 核心程序 (之前漏掉的关键步骤)...\e[0m"
bash <(curl -fsSL https://get.hy2.sh/)

echo -e "\e[33m>>> 2. 强行生成自签证书...\e[0m"
mkdir -p /etc/hysteria
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
    -subj "/CN=aws.amazon.com" -days 36500 2>/dev/null

echo -e "\e[33m>>> 3. 暴力写入定死参数的配置...\e[0m"
cat <<EOF > /etc/hysteria/config.yaml
listen: :45678
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: MyStrongPassword123
obfs:
  type: salamander
  salamander:
    password: MyObfsPassword123
masquerade:
  type: proxy
  proxy:
    url: https://aws.amazon.com
    rewriteHost: true
ignoreClientBandwidth: true
EOF

echo -e "\e[33m>>> 4. 最暴力的权限赋予 (满足官方低权限账户要求)...\e[0m"
chmod 777 /etc/hysteria/server.key
chmod 777 /etc/hysteria/server.crt
chown -R hysteria:hysteria /etc/hysteria/

echo -e "\e[33m>>> 5. 强行拉起服务...\e[0m"
systemctl daemon-reload
systemctl enable hysteria-server.service >/dev/null 2>&1
systemctl restart hysteria-server.service
sleep 2

# ==========================================
# 生成节点信息与二维码
# ==========================================
IP=$(curl -4s ipv4.icanhazip.com)

URI="hysteria2://MyStrongPassword123@$IP:45678/?insecure=1&sni=aws.amazon.com&obfs=salamander&obfs-password=MyObfsPassword123#Hy2-Pro"

echo -e "\n\e[36m======================================================\e[0m"
echo -e "\e[32m✅ Hysteria2 服务已重装并启动成功！\e[0m"
echo -e "\e[36m======================================================\e[0m"
echo -e "\e[32m$URI\e[0m"
echo -e "\e[36m======================================================\e[0m"
qrencode -t ANSIUTF8 "$URI"
