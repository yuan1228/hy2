#!/bin/bash

# ==========================================
# 极简专业版 (移除所有图标，防止乱码)
# ==========================================

# 颜色定义
RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
CYAN='\e[96m'
NC='\e[0m'

install_shortcut() {
    SCRIPT_PATH=$(readlink -f "$0")
    if [ "$SCRIPT_PATH" != "/usr/local/bin/hy2" ]; then
        cp "$SCRIPT_PATH" /usr/local/bin/hy2
        chmod +x /usr/local/bin/hy2
    fi
}

install_hy2() {
    clear
    echo "--- 部署 Hysteria2 ---"
    read -p "端口 [1-65535] (默认 45678): " INPUT_PORT
    PORT=${INPUT_PORT:-45678}
    read -p "连接密码 (默认随机): " INPUT_PASS
    PASSWORD=${INPUT_PASS:-$(openssl rand -hex 8)}
    read -p "伪装域名 (默认 aws.amazon.com): " INPUT_SNI
    SNI=${INPUT_SNI:-aws.amazon.com}
    OBFS_PASS=$(openssl rand -hex 6)

    echo "安装核心..."
    bash <(curl -fsSL https://get.hy2.sh/)

    echo "配置服务..."
    mkdir -p /etc/hysteria
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
        -subj "/CN=$SNI" -days 36500 2>/dev/null

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
    password: $OBFS_PASS
masquerade:
  type: proxy
  proxy:
    url: https://$SNI
    rewriteHost: true
ignoreClientBandwidth: true
EOF

    chmod 777 /etc/hysteria/server.key
    chmod 777 /etc/hysteria/server.crt
    chown -R hysteria:hysteria /etc/hysteria/
    systemctl restart hysteria-server.service
    
    IP=$(curl -4s ipv4.icanhazip.com)
    URI="hysteria2://$PASSWORD@$IP:$PORT/?insecure=1&sni=$SNI&obfs=salamander&obfs-password=$OBFS_PASS#Hy2-$PORT"
    echo "$URI" > /etc/hysteria/share_link.txt
    echo "安装完成。"
    read -n 1 -s -r -p "按任意键返回..."
}

install_shortcut

while true; do
    clear
    STATUS=$(systemctl is-active hysteria-server 2>/dev/null)
    echo "=================================="
    echo " Hysteria2 管理控制台"
    echo " 状态: $STATUS"
    echo "=================================="
    echo " 1. 安装 / 重置"
    echo " 2. 查看节点链接"
    echo " 3. 查看日志"
    echo " 4. BBR加速"
    echo " 5. 升级核心"
    echo " 6. 卸载"
    echo " 0. 退出"
    echo "=================================="
    read -p "选择 [0-6]: " choice
    case $choice in
        1) install_hy2 ;;
        2) cat /etc/hysteria/share_link.txt; echo; read -n 1 -s -r -p "按任意键返回..." ;;
        3) journalctl -u hysteria-server -f --output cat ;;
        4) echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf; echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf; sysctl -p; read -n 1 -s -r -p "按任意键..." ;;
        5) bash <(curl -fsSL https://get.hy2.sh/); systemctl restart hysteria-server.service ;;
        6) rm -rf /etc/hysteria/ /usr/local/bin/hysteria; systemctl stop hysteria-server; echo "已卸载"; sleep 1 ;;
        0) exit 0 ;;
    esac
done
