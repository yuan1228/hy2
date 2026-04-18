#!/bin/bash

# ==========================================
# HY2 瑞士军刀管理面板 (纯净专业版)
# ==========================================

# 颜色设置
RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
CYAN='\e[96m'
NC='\e[0m'

# --- 快捷指令部署 ---
install_shortcut() {
    SCRIPT_PATH=$(readlink -f "$0")
    if [ "$SCRIPT_PATH" != "/usr/local/bin/yuan" ]; then
        cp "$SCRIPT_PATH" /usr/local/bin/yuan
        chmod +x /usr/local/bin/yuan
    fi
}

# --- 核心部署 ---
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

    echo "正在拉取组件..."
    bash <(curl -fsSL https://get.hy2.sh/) >/dev/null 2>&1

    echo "生成配置与证书..."
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

    chown -R hysteria:hysteria /etc/hysteria/
    systemctl restart hysteria-server.service
    
    IP=$(curl -4s ipv4.icanhazip.com)
    URI="hysteria2://$PASSWORD@$IP:$PORT/?insecure=1&sni=$SNI&obfs=salamander&obfs-password=$OBFS_PASS#Hy2-$PORT"
    echo "$URI" > /etc/hysteria/share_link.txt
    
    echo "部署完毕。"
    read -n 1 -s -r -p "按任意键返回..."
}

install_shortcut

while true; do
    clear
    # 自动环境检测
    STATUS=$(systemctl is-active hysteria-server 2>/dev/null)
    [[ "$STATUS" == "active" ]] && S="RUNNING" || S="STOPPED"
    
    echo "=================================="
    echo " YUAN NETWORK CONTROL PANEL"
    echo " STATUS: $S | PORT: $(grep 'listen:' /etc/hysteria/config.yaml 2>/dev/null | awk '{print $2}' | tr -d ':')"
    echo "=================================="
    echo " 1. 安装/重置节点"
    echo " 2. 查看节点链接"
    echo " 3. 实时运行日志"
    echo " 4. BBR内核加速"
    echo " 5. 升级二进制内核"
    echo " 6. 深度卸载"
    echo " 0. 退出"
    echo "=================================="
    read -p "指令 [0-6]: " choice
    case $choice in
        1) install_hy2 ;;
        2) cat /etc/hysteria/share_link.txt 2>/dev/null; echo; read -n 1 -s -r -p "按任意键...";;
        3) journalctl -u hysteria-server -f --output cat ;;
        4) echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf; echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf; sysctl -p; read -n 1 -s -r -p "按任意键...";;
        5) bash <(curl -fsSL https://get.hy2.sh/); systemctl restart hysteria-server.service ;;
        6) rm -rf /etc/hysteria/ /usr/local/bin/hysteria; systemctl stop hysteria-server; echo "已卸载"; sleep 1 ;;
        0) exit 0 ;;
    esac
done
