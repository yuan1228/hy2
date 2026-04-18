#!/bin/bash
# --- 颜色与样式定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 核心变量获取 ---
get_ip() {
    IPv4=$(curl -4s -m 5 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$" || echo "")
    IPv6=$(curl -6s -m 5 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$" || echo "")
    IP=${IPv4:-$IPv6}
    if [ -z "$IP" ]; then
        echo -e "${RED}无法获取服务器 IP，请检查网络！${NC}"
        exit 1
    fi
}

# --- 快捷入口注入 ---
install_shortcut() {
    SCRIPT_PATH=$(readlink -f "$0")
    if [ "$SCRIPT_PATH" != "/usr/local/bin/yuan" ]; then
        cp "$SCRIPT_PATH" /usr/local/bin/yuan
        chmod +x /usr/local/bin/yuan
        echo -e "${GREEN}✅ 全局快捷命令 'yuan' 已安装！以后输入 yuan 即可呼出菜单。${NC}"
        sleep 1
    fi
}

# --- 1. 安装/配置 Hysteria2（核心优化版） ---
install_hy2() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN} 开始部署 Hysteria2 (优化抗封锁版) ${NC}"
    echo -e "${CYAN}======================================================${NC}"
   
    get_ip
   
    # 交互式参数
    read -p "👉 请输入监听端口 [默认 443]: " PORT
    PORT=${PORT:-443}
   
    read -p "👉 请输入连接密码 (默认随机32位): " PASSWORD
    [ -z "$PASSWORD" ] && PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
   
    read -p "👉 是否开启 Salamander 混淆？(y/n，默认 n): " ENABLE_OBFS
    if [[ "$ENABLE_OBFS" == "y" || "$ENABLE_OBFS" == "Y" ]]; then
        OBFS_PASS=$(tr -dc a-z0-9 </dev/urandom | head -c 16)
        OBFS_CONFIG="obfs:
  type: salamander
  password: $OBFS_PASS"
        OBFS_LINK="&obfs=salamander&obfs-password=$OBFS_PASS"
    else
        OBFS_CONFIG=""
        OBFS_LINK=""
    fi
   
    read -p "👉 请输入SNI伪装域名 (默认 aws.amazon.com): " SNI
    SNI=${SNI:-aws.amazon.com}

    echo -e "\n${YELLOW}>>> 正在安装依赖...${NC}"
    apt update -y || { echo -e "${RED}apt update 失败！${NC}"; exit 1; }
    apt install -y curl wget openssl qrencode net-tools || { echo -e "${RED}安装依赖失败！${NC}"; exit 1; }

    echo -e "${YELLOW}>>> 执行 Hysteria2 官方安装脚本...${NC}"
    bash <(curl -fsSL https://get.hy2.sh/) || { echo -e "${RED}官方安装脚本执行失败！${NC}"; exit 1; }

    echo -e "${YELLOW}>>> 生成自签名证书...${NC}"
    mkdir -p /etc/hysteria
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
        -subj "/CN=$SNI" -days 36500 2>/dev/null

    echo -e "${YELLOW}>>> 写入优化配置文件...${NC}"
    cat <<EOF > /etc/hysteria/config.yaml
listen: :$PORT

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: $PASSWORD

$OBFS_CONFIG

masquerade:
  type: proxy
  proxy:
    url: https://$SNI
    rewriteHost: true

# QUIC 优化参数（提升速度和稳定性）
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 16777216
  maxConnectionReceiveWindow: 33554432
  maxIdleTimeout: 30s
  activeConnectionIDLimit: 10
EOF

    echo -e "${YELLOW}>>> 重启 Hysteria2 服务...${NC}"
    systemctl daemon-reload
    systemctl enable --now hysteria-server.service

    # 生成分享链接
    URI="hysteria2://$PASSWORD@$IP:$PORT/?insecure=1&sni=$SNI$OBFS_LINK#Hy2-$PORT"

    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN} ✅ Hysteria2 部署成功！ ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "📍 服务器 IP     : $IP"
    echo -e "🔌 端口          : $PORT"
    echo -e "🔑 连接密码      : $PASSWORD"
    if [ -n "$OBFS_PASS" ]; then
        echo -e "👻 混淆密码      : $OBFS_PASS"
    fi
    echo -e "🛡️  SNI 伪装     : $SNI"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "🔗 节点链接："
    echo -e "${GREEN}${URI}${NC}"
    echo -e "${CYAN}======================================================${NC}"
    qrencode -t ANSIUTF8 "$URI"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "⚠️  必须在云服务商后台放行 UDP ${PORT} 端口！"
    echo -e "⚠️  输入 ${GREEN}yuan${NC} 即可再次呼出菜单"
    echo -e "按任意键返回主菜单..."
    read -n 1
}

# --- 2. 深度卸载 Hysteria2 ---
uninstall_hy2() {
    clear
    echo -e "${RED}>>> 正在彻底卸载 Hysteria2...${NC}"
    systemctl stop hysteria-server 2>/dev/null
    systemctl disable hysteria-server 2>/dev/null
    rm -f /etc/systemd/system/hysteria-server.service
    rm -f /usr/local/bin/hysteria
    rm -rf /etc/hysteria/
    rm -f /etc/systemd/system/hysteria-server.service.d/*.conf 2>/dev/null
    systemctl daemon-reload
    echo -e "${GREEN}✅ Hysteria2 已彻底卸载（包括配置和服务）。${NC}"
    sleep 2
}

# --- 主菜单（已删除3x-ui选项） ---
install_shortcut
while true; do
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN} 袁先生专属 Hysteria2 优化套件 (快捷指令: yuan) ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e " ${YELLOW}1.${NC} 安装/重置 Hysteria2（推荐）"
    echo -e " ${YELLOW}2.${NC} 深度卸载 Hysteria2"
    echo -e " ${YELLOW}0.${NC} 退出脚本"
    echo -e "${CYAN}======================================================${NC}"
    read -p "👉 请选择操作 [0-2]: " choice
    case $choice in
        1) install_hy2 ;;
        2) uninstall_hy2 ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}输入错误，请重试！${NC}"; sleep 1 ;;
    esac
done
