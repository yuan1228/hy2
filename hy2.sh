#!/bin/bash

# ==========================================
# YUAN CONTROL PANEL - HYSTERIA2 (V4.2)
# ==========================================

# 1. 预先定义所有函数 (确保在循环调用时可见)
install_hy2() {
    clear
    echo "--- 部署 Hysteria2 ---"
    read -p "端口 [1-65535] (默认 45678): " PORT
    PORT=${PORT:-45678}
    read -p "密码 (默认随机): " PASSWORD
    PASSWORD=${PASSWORD:-$(openssl rand -hex 8)}
    read -p "伪装域名 (默认 aws.amazon.com): " SNI
    SNI=${SNI:-aws.amazon.com}
    OBFS_PASS=$(openssl rand -hex 6)

    echo "正在拉取核心..."
    bash <(curl -fsSL https://get.hy2.sh/) >/dev/null 2>&1

    echo "正在配置..."
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

    chmod 777 /etc/hysteria/server.key /etc/hysteria/server.crt
    chown -R hysteria:hysteria /etc/hysteria/
    systemctl restart hysteria-server.service
    
    IP=$(curl -4s ipv4.icanhazip.com)
    URI="hysteria2://$PASSWORD@$IP:$PORT/?insecure=1&sni=$SNI&obfs=salamander&obfs-password=$OBFS_PASS#Hy2-$PORT"
    echo "$URI" > /etc/hysteria/share_link.txt
    echo "部署完毕。"
    read -n 1 -s -r -p "按任意键返回..."
}

show_node() {
    if [ -f "/etc/hysteria/share_link.txt" ]; then
        echo -e "\n节点链接:"
        cat /etc/hysteria/share_link.txt
        echo -e "\n"
    else
        echo "未找到节点信息。"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}

# 2. 快捷指令安装函数
install_shortcut() {
    if [ ! -f "/usr/local/bin/yuan" ]; then
        cp "$0" /usr/local/bin/yuan
        chmod +x /usr/local/bin/yuan
    fi
}

# 3. 确保快捷指令存在
install_shortcut

# 4. 主循环
while true; do
    clear
    STATUS=$(systemctl is-active hysteria-server 2>/dev/null)
    PORT_VAL=$(grep 'listen:' /etc/hysteria/config.yaml 2>/dev/null | awk '{print $2}' | tr -d ':')
    
    echo "=================================="
    echo " YUAN CONTROL PANEL"
    echo " STATUS: ${STATUS:-inactive} | PORT: ${PORT_VAL:-N/A}"
    echo "=================================="
    echo " 1. 安装/重置节点"
    echo " 2. 查看节点信息"
    echo " 3. 运行日志"
    echo " 4. BBR加速"
    echo " 5. 升级核心"
    echo " 6. 卸载"
    echo " 0. 退出"
    echo "=================================="
    read -p "指令 [0-6]: " choice
    case $choice in
        1) install_hy2 ;;
        2) show_node ;;
        3) journalctl -u hysteria-server -f --output cat ;;
        4) echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf; echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf; sysctl -p; read -n 1 -s -r -p "按任意键...";;
        5) bash <(curl -fsSL https://get.hy2.sh/); systemctl restart hysteria-server.service ;;
        6) rm -rf /etc/hysteria/ /usr/local/bin/hysteria; systemctl stop hysteria-server; echo "已卸载"; sleep 1 ;;
        0) exit 0 ;;
    esac
done
