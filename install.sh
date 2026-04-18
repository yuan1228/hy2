#!/bin/bash
# --- 快捷入口安装 ---
if [ ! -f "/usr/local/bin/yuan" ]; then
    cp "$0" /usr/local/bin/yuan
    chmod +x /usr/local/bin/yuan
fi

# --- 颜色定义（美化专用）---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- 主循环界面 ---
while true; do
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}   项目地址: https://github.com/yuan1228/hy2${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # === 修正后的 YUAN 艺术字（已居中对齐、无错位）===
    echo -e "${GREEN}"
    echo "               __ __ _ _ _ _ _                  "
    echo "              \ \/ / | | | | / \ | \ | |        "
    echo "               \ / | | | | / _ \ | \| |         "
    echo "                / \ | |_| |/ ___ \| |\ |        "
    echo "               /_/\_\ \___/_/ \_\_| \_|         "
    echo -e "${NC}"
    
    echo -e "${BOLD}${BLUE}            HY2 一键工具${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}快捷键已设置为 ${BOLD}yuan${NC}${GREEN}，下次运行直接输入 ${BOLD}yuan${NC}${GREEN} 即可快速启动${NC}"
    echo ""
    echo -e " ${GREEN}1.${NC} 安装/重置 Hysteria2"
    echo -e " ${GREEN}2.${NC} 查看节点链接"
    echo -e " ${GREEN}3.${NC} 运行日志"
    echo -e " ${GREEN}4.${NC} BBR加速"
    echo -e " ${GREEN}5.${NC} 升级内核"
    echo -e " ${GREEN}6.${NC} 深度卸载"
    echo -e " ${RED}0.${NC} 退出"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -ne "${YELLOW}指令 [0-6]: ${NC}"
    read -r choice
   
    case $choice in
        1)
            read -p "端口 [1-65535] (默认 45678): " P
            read -p "密码: " PASS
            read -p "伪装域名 (默认 aws.amazon.com): " SNI
            bash <(curl -fsSL https://get.hy2.sh/) >/dev/null 2>&1
            mkdir -p /etc/hysteria
            openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
                -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
                -subj "/CN=${SNI:-aws.amazon.com}" -days 36500 2>/dev/null
            cat <<EOF > /etc/hysteria/config.yaml
listen: :${P:-45678}
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: ${PASS:-$(openssl rand -hex 8)}
obfs:
  type: salamander
  salamander:
    password: $(openssl rand -hex 6)
masquerade:
  type: proxy
  proxy:
    url: https://${SNI:-aws.amazon.com}
    rewriteHost: true
ignoreClientBandwidth: true
EOF
            chown -R hysteria:hysteria /etc/hysteria/
            systemctl restart hysteria-server.service
            IP=$(curl -4s ipv4.icanhazip.com)
            echo "hysteria2://${PASS:-$(openssl rand -hex 8)}@$IP:${P:-45678}/?insecure=1&sni=${SNI:-aws.amazon.com}#HY2" > /etc/hysteria/share_link.txt
            echo -e "${GREEN}安装完成。${NC}" && read -n 1 -s -r -p "按任意键继续..." ;;
        2) 
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            cat /etc/hysteria/share_link.txt 2>/dev/null || echo -e "${RED}无配置${NC}"
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            read -n 1 -s -r -p "按任意键继续..." ;;
        3) journalctl -u hysteria-server -f --output cat ;;
        4) echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf; echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf; sysctl -p; 
           echo -e "${GREEN}BBR加速已开启${NC}" && read -n 1 -s -r -p "按任意键继续..." ;;
        5) bash <(curl -fsSL https://get.hy2.sh/); systemctl restart hysteria-server.service; 
           echo -e "${GREEN}内核升级完成${NC}" && read -n 1 -s -r -p "按任意键继续..." ;;
        6) rm -rf /etc/hysteria/ /usr/local/bin/hysteria; systemctl stop hysteria-server; echo -e "${RED}已深度卸载${NC}"; sleep 1 ;;
        0) exit 0 ;;
    esac
done
