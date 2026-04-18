#!/bin/bash

# ==========================================
# 终极硬编码防爆版 (解决变量丢失和权限问题)
# ==========================================

echo -e "\e[33m>>> 1. 强行生成自签证书...\e[0m"
mkdir -p /etc/hysteria
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
    -subj "/CN=aws.amazon.com" -days 36500 2>/dev/null

echo -e "\e[33m>>> 2. 暴力写入定死参数的配置...\e[0m"
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

echo -e "\e[33m>>> 3. 最暴力的权限赋予...\e[0m"
chmod 777 /etc/hysteria/server.key
chmod 777 /etc/hysteria/server.crt
chown -R hysteria:hysteria /etc/hysteria/

echo -e "\e[33m>>> 4. 强行拉起服务并检查状态...\e[0m"
systemctl daemon-reload
systemctl enable hysteria-server.service >/dev/null 2>&1
systemctl restart hysteria-server.service

sleep 2
systemctl status hysteria-server.service --no-pager

echo -e "\n\e[36m======================================================\e[0m"
echo -e "\e[32m✅ 如果上面看到绿色的 active (running)，则说明启动成功！\e[0m"
echo -e "\e[36m======================================================\e[0m"
echo -e "\e[33m请在客户端手动填写以下信息：\e[0m"
echo -e "IP: \e[32m你的服务器公网IP\e[0m"
echo -e "端口: \e[32m45678\e[0m"
echo -e "密码: \e[32mMyStrongPassword123\e[0m"
echo -e "SNI: \e[32maws.amazon.com\e[0m"
echo -e "混淆密码: \e[32mMyObfsPassword123\e[0m"
echo -e "跳过证书验证: \e[32mTrue (开启)\e[0m"
echo -e "\e[36m======================================================\e[0m"
