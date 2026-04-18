#!/bin/bash

# ==========================================
# Hysteria2 专业版管理控制台 (带交互自定义)
# ==========================================

# 颜色定义
RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
CYAN='\e[96m'
NC='\e[0m'

# --- 全局快捷键注入 ---
install_shortcut() {
    SCRIPT_PATH=$(readlink -f "$0")
    if [ "$SCRIPT_PATH" != "/usr/local/bin/hy2" ]; then
        cp "$SCRIPT_PATH" /usr/local/bin/hy2
        chmod +x /usr/local/bin/hy2
        echo -e "${GREEN}✅ 快捷命令 'hy2' 已激活！随时输入 hy2 唤出面板。${NC}\n"
        sleep 1
    fi
}

# --- 1. 交互式部署模块 ---
install_hy2() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}             部署 Hysteria2 (专业自定义版)            ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    # 交互式获取参数
    read -p "👉 1. 请输入自定义 UDP 端口 [1-65535] (默认 45678): " INPUT_PORT
    PORT=${INPUT_PORT:-45678}

    # 使用 openssl 保证绝对能生成密码，避免 /dev/urandom 为空导致的 Bug
    SAFE_RAND_PASS=$(openssl rand -hex 8 2>/dev/null || echo "Hy2SafePass2026")
    read -p "👉 2. 请输入自定义连接密码 (默认生成 16 位高强密码): " INPUT_PASS
    PASSWORD=${INPUT_PASS:-$SAFE_RAND_PASS}

    read -p "👉 3. 请输入伪装 SNI 域名 (默认 aws.amazon.com): " INPUT_SNI
    SNI=${INPUT_SNI:-aws.amazon.com}

    # 混淆密码强行随机，防止用户乱填导致长度不足 4 字节崩溃
    OBFS_PASSWORD=$(openssl rand -hex 6 2>/dev/null || echo "Obfs2026")

    echo -e "\n${YELLOW}>>> 初始化基础环境...${NC}"
    apt-get update -y >/dev/null 2>&1
    apt-get install -y qrencode curl openssl >/dev/null 2>&1

    echo -e "${YELLOW}>>> 拉取官方核心组件...${NC}"
    bash <(curl -fsSL https://get.hy2.sh/)

    echo -e "${YELLOW}>>> 生成底层自签证书...${NC}"
    mkdir -p /etc/hysteria
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
        -subj "/CN=$SNI" -days 36500 2>/dev/null

    echo -e "${YELLOW}>>> 写入自定义配置...${NC}"
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
    password: $OBFS_PASSWORD
masquerade:
  type: proxy
  proxy:
    url: https://$SNI
    rewriteHost: true
ignoreClientBandwidth: true
EOF

    echo -e "${YELLOW}>>> 修复官方权限隔离...${NC}"
    chmod 777 /etc/hysteria/server.key
    chmod 777 /etc/hysteria/server.crt
    chown -R hysteria:hysteria /etc/hysteria/

    echo -e "${YELLOW}>>> 启动守护进程...${NC}"
    systemctl daemon-reload
    systemctl enable hysteria-server.service >/dev/null 2>&1
    systemctl restart hysteria-server.service
    sleep 2

    IP=$(curl -4s ipv4.icanhazip.com)
    URI="hysteria2://$PASSWORD@$IP:$PORT/?insecure=1&sni=$SNI&obfs=salamander&obfs-password=$OBFS_PASSWORD#Hy2-Pro-$PORT"
    echo "$URI" > /etc/hysteria/share_link.txt

    show_node "$URI" "$PORT"
}

# --- 2. 显示节点 ---
show_node() {
    URI=$1
    CURRENT_PORT=$2
    if [ -z "$URI" ]; then
        if [ -f "/etc/hysteria/share_link.txt" ]; then
            URI=$(cat /etc/hysteria/share_link.txt)
        else
            echo -e "${RED}未找到节点信息，请先进行安装！${NC}"
            sleep 2
            return
        fi
    fi
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}✅ 节点已生成 (请确保云防火墙已放行 UDP 端口)${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "\e[32m$URI\e[0m"
    echo -e "${CYAN}======================================================${NC}"
    qrencode -t ANSIUTF8 "$URI"
    echo -e "${CYAN}======================================================${NC}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# --- 3. 实时日志与监控 ---
show_logs() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}📡 正在查看实时运行日志 (按 Ctrl+C 退出)${NC}"
    echo -e "${CYAN}======================================================${NC}"
    journalctl -u hysteria-server -f --output cat
}

# --- 4. 一键 BBR 拥塞控制 ---
enable_bbr() {
    clear
    echo -e "${YELLOW}>>> 正在优化 Linux 内核网络参数...${NC}"
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    
    if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        echo -e "${GREEN}✅ BBR 加速已开启。${NC}"
    else
        echo -e "${RED}❌ BBR 开启失败，可能内核不兼容。${NC}"
    fi
    sleep 3
}

# --- 5. 核心平滑升级 ---
update_core() {
    clear
    echo -e "${YELLOW}>>> 正在升级 Hysteria2 核心...${NC}"
    bash <(curl -fsSL https://get.hy2.sh/)
    systemctl restart hysteria-server.service
    echo -e "${GREEN}✅ 核心升级完毕，已自动重启服务。${NC}"
    sleep 3
}

# --- 6. 物理级卸载 ---
uninstall_hy2() {
    clear
    echo -e "${RED}>>> 正在执行底层卸载清理...${NC}"
    systemctl stop hysteria-server.service 2>/dev/null
    systemctl disable hysteria-server.service 2>/dev/null
    rm -f /etc/systemd/system/hysteria-server*.service 2>/dev/null
    rm -f /usr/local/bin/hysteria 2>/dev/null
    rm -rf /etc/hysteria/ 2>/dev/null
    systemctl daemon-reload
    echo -e "${GREEN}✅ Hysteria2 相关数据已从物理层抹除。${NC}"
    sleep 2
}

# --- 主菜单 ---
install_shortcut

while true; do
    clear
    STATUS=$(systemctl is-active hysteria-server 2>/dev/null)
    if [ "$STATUS" == "active" ]; then
        STATUS_TEXT="${GREEN}[运行中]${NC}"
    else
        STATUS_TEXT="${RED}[未运行 / 未安装]${NC}"
    fi

    echo -e "${CYAN}======================================================${NC}"
    echo -e "          Hysteria2 专业管理控制台 (快捷键: hy2)      "
    echo -e "${CYAN}======================================================${NC}"
    echo -e " 当前服务状态: $STATUS_TEXT"
    echo -e "${CYAN}------------------------------------------------------${NC}"
    echo -e " ${YELLOW}1.${NC} 🚀 安装 / 重置 Hysteria2 (自定义参数)"
    echo -e " ${YELLOW}2.${NC} 👁️  查看当前节点链接与二维码"
    echo -e " ${YELLOW}3.${NC} 📈 查看底层实时运行日志"
    echo -e " ${YELLOW}4.${NC} ⚡ 开启 BBR 网络内核加速"
    echo -e " ${YELLOW}5.${NC} 🔄 无损升级二进制核心版本"
    echo -e " ${YELLOW}6.${NC} 🗑️  彻底卸载系统残留痕迹"
    echo -e " ${YELLOW}0.${NC} 🚪 退出控制台"
    echo -e "${CYAN}======================================================${NC}"
    read -p "👉 请输入指令 [0-6]: " choice

    case $choice in
        1) install_hy2 ;;
        2) show_node "" "" ;;
        3) show_logs ;;
        4) enable_bbr ;;
        5) update_core ;;
        6) uninstall_hy2 ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}指令无效，请重新输入！${NC}"; sleep 1 ;;
    esac
done
