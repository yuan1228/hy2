#!/bin/bash

# ====================================================
# 严格遵循 Hysteria2 官方文档规范的部署脚本
# 核心修复：解决官方低权限 hysteria 用户的证书读取阻断问题
# ====================================================

# 1. 基础参数定义 (可在此处手动修改)
PORT=45678
PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
OBFS_PASSWORD=$(tr -dc a-z0-9 </dev/urandom | head -c 8)
SNI="aws.amazon.com"

# 获取本机 IP
IP=$(curl -4s -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")
if [ -z "$IP" ]; then
    IP=$(curl -6s -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")
fi

echo -e "\e[33m>>> 1. 执行官方标准安装管道...\e[0m"
# 严格使用官方推荐的安装命令
bash <(curl -fsSL https://get.hy2.sh/)

echo -e "\e[33m>>> 2. 生成 ECDSA 证书与指纹...\e[0m"
# 在官方指定目录生成证书
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout /etc/hysteria/server.key \
    -out /etc/hysteria/server.crt \
    -subj "/CN=$SNI" -days 36500 2>/dev/null

# 提取指纹 (用于客户端防劫持)
PIN_SHA256=$(openssl x509 -in /etc/hysteria/server.crt -outform DER | sha256sum | awk '{print $1}')

echo -e "\e[33m>>> 3. 严格遵循官方 v2 格式写入配置...\e[0m"
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
  password: $OBFS_PASSWORD

masquerade:
  type: proxy
  proxy:
    url: https://$SNI
    rewriteHost: true

# 官方推荐：忽略客户端带宽请求，由服务端 Brutal 算法强制接管
ignoreClientBandwidth: true
EOF

echo -e "\e[33m>>> 4. [核心修复] 执行官方文档要求的权限隔离...\e[0m"
# 官方创建的 daemon 属于 hysteria 用户，必须把目录和文件所有权移交，否则服务启动必死！
chown -R hysteria:hysteria /etc/hysteria/

echo -e "\e[33m>>> 5. 启动并校验守护进程...\e[0m"
systemctl daemon-reload
systemctl enable hysteria-server.service >/dev/null 2>&1
systemctl restart hysteria-server.service

# 暂停 2 秒等待服务完全启动以检测真实状态
sleep 2 
SERVICE_STATUS=$(systemctl is-active hysteria-server)

if [ "$SERVICE_STATUS" = "active" ]; then
    echo -e "\e[32m[OK] Hysteria2 官方服务已成功启动运行！\e[0m"
else
    echo -e "\e[31m[ERROR] 服务启动失败！请运行 'journalctl -u hysteria-server -e' 查看官方报错日志。\e[0m"
    exit 1
fi

echo -e "\n\e[36m======================================================\e[0m"
echo -e "\e[32m✅ 官方标准节点部署完成\e[0m"
echo -e "\e[36m======================================================\e[0m"
# 严格按照官方 URI 规范生成链接，不使用即将废弃的 insecure=1
URI="hysteria2://$PASSWORD@$IP:$PORT/?sni=$SNI&obfs=salamander&obfs-password=$OBFS_PASSWORD&pinSHA256=$PIN_SHA256#Hy2-Official"
echo -e "\e[32m$URI\e[0m"
echo -e "\e[36m======================================================\e[0m"
echo -e "\e[31m最终防线：请务必确保 AWS 控制台已放行 UDP $PORT 端口！\e[0m"
