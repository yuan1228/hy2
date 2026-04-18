#!/bin/bash

# --- 自动更新机制 ---
REMOTE_URL="https://raw.githubusercontent.com/yuan1228/hy2/refs/heads/main/install.sh"
if [ -f "/usr/local/bin/yuan" ] && [ "$1" != "--no-update" ]; then
    TMP_FILE=$(mktemp)
    curl -sL "$REMOTE_URL" > "$TMP_FILE"
    if ! cmp -s "$TMP_FILE" /usr/local/bin/yuan; then
        mv "$TMP_FILE" /usr/local/bin/yuan
        chmod +x /usr/local/bin/yuan
        echo "更新完成，请重新输入 yuan"
        exit 0
    fi
    rm -f "$TMP_FILE"
fi

if [ ! -f "/usr/local/bin/yuan" ]; then
    cp "$0" /usr/local/bin/yuan
    chmod +x /usr/local/bin/yuan
fi

# --- 核心部署函数 (已支持自定义变量) ---
deploy_hy2() {
    # 交互式获取配置
    read -p "请输入端口 (默认 45678): " P
    P=${P:-45678}
    read -p "请输入密码: " PASS
    read -p "请输入伪装域名 (默认 aws.amazon.com): " SNI
    SNI=${SNI:-aws.amazon.com}

    echo -e "\e[33m>>> 正在安装核心并部署配置...\e[0m"
    bash <(curl -fsSL https://get.hy2.sh/) >/dev/null 2>&1
    mkdir -p /etc/hysteria
    
    # 生成证书
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
        -subj "/CN=$SNI" -days 36500 2>/dev/null
    
    # 写入配置文件
    cat <<EOF > /etc/hysteria/config.yaml
listen: :$P
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASS
obfs:
  type: salamander
  salamander:
    password: $(openssl rand -hex 6)
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
    
    # 生成节点链接
    IP=$(curl -4s ipv4.icanhazip.com)
    LOC=$(curl -s http://ip-api.com/line/?fields=countryCode)
    [ -z "$LOC" ] && LOC="Unknown"
    URI="hysteria2://$PASS@$IP:$P/?insecure=1&sni=$SNI#${LOC}_HY2"
    echo "$URI" > /etc/hysteria/share_link.txt
    
    echo -e "\e[32m部署成功！端口: $P, 域名: $SNI\e[0m"
    read -n 1 -s -r -p "按任意键返回..."
}

# --- 主循环界面 ---
while true; do
    clear
    echo "===================================================="
    echo " 项目地址: https://github.com/yuan1228/hy2"
    echo " 核心架构: H Y S T E R I A  2  P R O [自定义版]"
    echo "===================================================="
    echo " 1. 安装/自定义配置"
    echo " 2. 查看节点链接"
    echo " 3. 运行日志"
    echo " 4. BBR加速"
    echo " 5. 升级内核"
    echo " 6. 深度卸载"
    echo " 0. 退出"
    echo "===================================================="
    read -p "指令 [0-6]: " choice
    case $choice in
        1) deploy_hy2 ;;
        2) cat /etc/hysteria/share_link.txt 2>/dev/null || echo "无配置"; echo; read -n 1 -s -r -p "按任意键..." ;;
        3) journalctl -u hysteria-server -f --output cat ;;
        4) echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf; echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf; sysctl -p; read -n 1 -s -r -p "按任意键..." ;;
        5) bash <(curl -fsSL https://get.hy2.sh/); systemctl restart hysteria-server.service ;;
        6) rm -rf /etc/hysteria/ /usr/local/bin/hysteria; systemctl stop hysteria-server; echo "已卸载"; sleep 1 ;;
        0) exit 0 ;;
    esac
done
