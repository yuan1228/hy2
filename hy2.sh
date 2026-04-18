#!/bin/bash

# --- 颜色与样式定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 核心变量获取 ---
get_ip() {
    IPv4=$(curl -4s -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")
    IPv6=$(curl -6s -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")
    IP=${IPv4:-$IPv6}
}

# --- 快捷入口注入 ---
install_shortcut() {
    SCRIPT_PATH=$(readlink -f "$0")
    if [ "$SCRIPT_PATH" != "/usr/local/bin/yuan" ]; then
        cp "$SCRIPT_PATH" /usr/local/bin/yuan
        chmod +x /usr/local/bin/yuan
        echo -e "${GREEN}✅ 全局快捷命令 'yuan' 已安装！以后随时输入 yuan 即可呼出本面板。${NC}"
        sleep 1
    fi
}

# --- 1. 安装/配置 Hy2 ---
install_hy2() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}             开始部署 Hysteria2 (原生抗封锁版)          ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    get_ip
    
    # 交互式自定义参数
    read -p "👉 1. 请输入端口 [1-65535] (默认 45678): " PORT
    PORT=${PORT:-45678}
    
    read -p "👉 2. 请输入连接密码 (默认随机): " PASSWORD
    [ -z "$PASSWORD" ] && PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    
    read -p "👉 3. 请输入混淆密码 (默认随机): " OBFS_PASS
    [ -z "$OBFS_PASS" ] && OBFS_PASS=$(tr -dc a-z0-9 </dev/urandom | head -c 8)
    
    read -p "👉 4. 请输入SNI伪装域名 (默认 aws.amazon.com): " SNI
    SNI=${SNI:-aws.amazon.com}

    echo -e "\n${YELLOW}>>> 正在安装依赖工具...${NC}"
    apt update -y > /dev/null 2>&1
    apt install -y curl wget openssl qrencode net-tools > /dev/null 2>&1

    echo -e "${YELLOW}>>> 正在执行 Hy2 官方安装脚本...${NC}"
    bash <(curl -fsSL https://get.hy2.sh/)

    echo -e "${YELLOW}>>> 正在生成 $SNI 伪装证书...${NC}"
    mkdir -p /etc/hysteria
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
        -subj "/CN=$SNI" -days 36500 2>/dev/null

    echo -e "${YELLOW}>>> 正在写入高阶抗封锁配置文件...${NC}"
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
  password: $OBFS_PASS
masquerade:
  type: proxy
  proxy:
    url: https://$SNI
    rewriteHost: true
EOF

    echo -e "${YELLOW}>>> 正在启动 Hysteria2 服务...${NC}"
    systemctl daemon-reload
    systemctl enable hysteria-server.service > /dev/null 2>&1
    systemctl restart hysteria-server.service

    # 生成分享链接
    URI="hysteria2://$PASSWORD@$IP:$PORT/?insecure=1&sni=$SNI&obfs=salamander&obfs-password=$OBFS_PASS#Hy2-$PORT"

    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}             ✅ Hysteria2 节点部署成功！              ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "📍 ${YELLOW}服务器 IP${NC}  : $IP"
    echo -e "🔌 ${YELLOW}UDP 端口${NC}   : $PORT"
    echo -e "🔑 ${YELLOW}连接密码${NC}   : $PASSWORD"
    echo -e "👻 ${YELLOW}混淆密码${NC}   : $OBFS_PASS"
    echo -e "🛡️  ${YELLOW}SNI 伪装${NC}   : $SNI"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "🔗 ${GREEN}节点链接 (推荐直接复制以下完整链接):${NC}"
    echo -e "${URI}"
    echo -e "${CYAN}======================================================${NC}"
    qrencode -t ANSIUTF8 "$URI"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "⚠️  ${RED}重要提醒${NC}: 必须在云服务商防火墙放行 UDP ${PORT} 端口！"
    echo -e "⚠️  ${RED}快捷提醒${NC}: 以后在终端输入 ${GREEN}yuan${NC} 即可直接呼出本菜单！"
    echo -e "按任意键返回主菜单..."
    read -n 1
}

# --- 2. 一键卸载 Hy2 ---
uninstall_hy2() {
    clear
    echo -e "${RED}>>> 正在彻底卸载 Hysteria2...${NC}"
    systemctl stop hysteria-server 2>/dev/null
    systemctl disable hysteria-server 2>/dev/null
    rm -f /etc/systemd/system/hysteria-server.service
    rm -f /usr/local/bin/hysteria
    rm -rf /etc/hysteria/
    systemctl daemon-reload
    echo -e "${GREEN}✅ Hysteria2 已从系统中物理抹除。${NC}"
    sleep 2
}

# --- 3. 一键卸载 3x-ui ---
uninstall_3xui() {
    clear
    echo -e "${RED}>>> 正在彻底卸载 3x-ui 面板...${NC}"
    systemctl stop x-ui 2>/dev/null
    systemctl disable x-ui 2>/dev/null
    rm -f /etc/systemd/system/x-ui.service
    rm -rf /usr/local/x-ui/
    rm -rf /etc/x-ui/
    rm -f /usr/bin/x-ui
    systemctl daemon-reload
    echo -e "${GREEN}✅ 3x-ui 面板及其所有数据已彻底清除。${NC}"
    sleep 2
}

# --- 主菜单逻辑 ---
install_shortcut

while true; do
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}          袁先生的专属网络优化套件 (快捷指令: yuan)     ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e " ${YELLOW}1.${NC} 安装/重置 Hysteria2 (原生二进制 + 抗封锁)"
    echo -e " ${YELLOW}2.${NC} 深度卸载 Hysteria2"
    echo -e " ${YELLOW}3.${NC} 深度卸载 3x-ui 面板"
    echo -e " ${YELLOW}0.${NC} 退出脚本"
    echo -e "${CYAN}======================================================${NC}"
    read -p "👉 请选择操作 [0-3]: " choice

    case $choice in
        1) install_hy2 ;;
        2) uninstall_hy2 ;;
        3) uninstall_3xui ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}输入错误，请重试！${NC}"; sleep 1 ;;
    esac
done
