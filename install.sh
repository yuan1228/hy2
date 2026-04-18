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

# --- 部署函数 ---
deploy_hy2() {
    RAND_PORT=$((40000 + RANDOM % 10000))
    RAND_PASS=$(openssl rand -hex 8)
    
    read -p "请输入端口 (默认 $RAND_PORT): " P
    P=${P:-$RAND_PORT}
    read -p "请输入密码 (默认 $RAND_PASS): " PASS
    PASS=${PASS:-$RAND_PASS}
    read -p "请输入伪装域名 (默认 aws.amazon.com): " SNI
    SNI=${SNI:-aws.amazon.com}

    echo -e "\n\e[36m[1/5] 正在从官方获取 Hysteria2 核心...\e[0m"
    bash <(curl -fsSL https://get.hy2.sh/)
    
    echo -e "\e[36m[2/5] 正在创建配置目录...\e[0m"
    mkdir -p /etc/hysteria
    
    echo -e "\e[36m[3/5] 正在生成自签名 TLS 证书 (SNI: $SNI)...\e[0m"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
        -subj "/CN=$SNI" -days 36500 2>/dev/null
    
    echo -e "\e[36m[4/5] 正在写入配置文件...\e[0m"
    OBFS_PASS=$(openssl rand -hex 6)
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
    password: $OBFS_PASS
masquerade:
  type: proxy
  proxy:
    url: https://$SNI
    rewriteHost: true
ignoreClientBandwidth: true
EOF
    
    echo -e "\e[36m[5/5] 正在赋予权限并启动服务...\e[0m"
    chown -R hysteria:hysteria /etc/hysteria/
    systemctl restart hysteria-server.service
    
    IP=$(curl -4s ipv4.icanhazip.com)
    LOC=$(curl -s http://ip-api.com/line/?fields=countryCode)
    [ -z "$LOC" ] && LOC="Unknown"
    URI="hysteria2://$PASS@$IP:$P/?insecure=1&sni=$SNI&obfs=salamander&obfs-password=$OBFS_PASS#${LOC}_HY2"
    echo "$URI" > /etc/hysteria/share_link.txt
    
    echo -e "\n\e[32m部署完成！服务已就绪。\e[0m"
    read -n 1 -s -r -p "按任意键返回..."
}

# --- 加速中心 ---
set_bbr() {
    echo -e "\e[36m正在应用网络加速策略...\e[0m"
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    read -p "请选择队列算法 (1: FQ, 2: CAKE): " bbr_choice
    if [ "$bbr_choice" == "1" ]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    else
        echo "net.core.default_qdisc=cake" >> /etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1
    echo -e "\e[32m加速配置已生效！\e[0m"
    read -n 1 -s -r -p "按任意键返回..."
}

# --- 主循环 ---
while true; do
    clear
    echo "===================================================="
    echo "       HY2 一键管理工具 (Progress Version) by yuan1228"
    echo "       本项目链接：https://github.com/yuan1228/hy2"
    echo "                               （由AI制作仅供学习参考）"
    echo "===================================================="
    echo " 1. 一键安装 / 覆盖配置"
    echo " 2. 查看节点链接"
    echo " 3. 安装原版BBR (FQ/CAKE)"
    echo " 4. 查看运行日志"
    echo " 5. 卸载"
    echo " 0. 退出"
    echo "===================================================="
    read -p "指令 [0-5]: " choice
    case $choice in
        1) deploy_hy2 ;;
        2) cat /etc/hysteria/share_link.txt 2>/dev/null || echo "无配置"; echo; read -n 1 -s -r -p "按任意键..." ;;
        3) set_bbr ;;
        4) journalctl -u hysteria-server -f --output cat ;;
        5) rm -rf /etc/hysteria/ /usr/local/bin/hysteria; systemctl stop hysteria-server; echo "已卸载"; sleep 1 ;;
        0) exit 0 ;;
    esac
done
