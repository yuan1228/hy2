#!/bin/bash
# Hysteria2 终极抗封锁版部署脚本 (自动生成二维码)

# 1. 安装必要的工具
echo ">>> 正在安装二维码生成工具..."
sudo apt update -y > /dev/null 2>&1
sudo apt install -y qrencode > /dev/null 2>&1

# 2. 设定核心参数
PORT=45678
PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
OBFS_PASS=$(tr -dc a-z0-9 </dev/urandom | head -c 8) # 混淆密码
IP=$(curl -s ipv4.icanhazip.com)
SNI="aws.amazon.com"
NODE_NAME="AWS-Hy2-Pro"

# 3. 清理与环境准备
docker rm -f hy2 2>/dev/null
sudo mkdir -p /opt/hy2

# 4. 生成 AWS 伪装证书
sudo openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /opt/hy2/server.key -out /opt/hy2/server.crt -days 3650 \
  -subj "/C=US/ST=CA/L=LosAngeles/O=Amazon/OU=AWS/CN=$SNI" 2>/dev/null

# 5. 写入极客版 Hy2 配置文件 (加入 Salamander 混淆)
sudo bash -c "cat <<EOF > /opt/hy2/config.yaml
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASSWORD
obfs:
  type: salamander
  password: $OBFS_PASS
masquerade:
  type: proxy
  proxy:
    url: https://$SNI
    rewriteHost: true
EOF"

# 6. 启动容器
echo ">>> 正在启动 Hysteria2 抗封锁容器..."
sudo docker run -d --name hy2 --restart always \
  --network host \
  -v /opt/hy2:/etc/hysteria \
  tobyxdd/hysteria server -c /etc/hysteria/config.yaml > /dev/null 2>&1

# 7. 生成连接 URI
URI="hysteria2://$PASSWORD@$IP:$PORT/?insecure=1&sni=$SNI&obfs=salamander&obfsParam=$OBFS_PASS#$NODE_NAME"

# 8. 输出结果与二维码
echo ""
echo "======================================================"
echo "✅ Hysteria2 极致抗封锁节点部署成功！"
echo "======================================================"
echo "🔗 节点链接 (一键复制):"
echo -e "\033[32m$URI\033[0m"
echo "======================================================"
echo "📱 请使用 v2rayNG / Clash Meta / NekoBox 扫描下方二维码导入："
echo ""
qrencode -t ANSIUTF8 "$URI"
echo ""
echo "======================================================"
echo "⚠️ 致命提醒: 请务必确保在 AWS 防火墙中放行了 UDP 端口: $PORT"
