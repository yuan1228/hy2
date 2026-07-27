#!/bin/bash

# ===================================================
#      HY2 一键管理工具 (Ultimate Progress Version)
#      本项目链接：https://github.com/yuan1228/hy2
#                             （由AI制作仅供学习参考）
#                                          by yuan1228
# ===================================================

# --- 自动更新机制 ---
REMOTE_URL="https://raw.githubusercontent.com/yuan1228/hy2/refs/heads/main/install.sh"
if [ -f "/usr/local/bin/yuan" ] && [ "$1" != "--no-update" ]; then
    TMP_FILE=$(mktemp)
    curl -sL "$REMOTE_URL" > "$TMP_FILE"
    if [ -s "$TMP_FILE" ] && ! cmp -s "$TMP_FILE" /usr/local/bin/yuan; then
        mv "$TMP_FILE" /usr/local/bin/yuan
        chmod +x /usr/local/bin/yuan
        echo "更新完成，请重新输入 yuan"
        rm -f "$TMP_FILE"
        exit 0
    fi
    rm -f "$TMP_FILE"
fi

if [ ! -f "/usr/local/bin/yuan" ] && [ -f "$0" ] && [ "$0" != "bash" ]; then
    cp "$0" /usr/local/bin/yuan
    chmod +x /usr/local/bin/yuan
fi

# --- 基础依赖环境检查 ---
check_deps() {
    echo -e "\e[36m正在检测并安装基础依赖 (openssl/curl/iptables)...\e[0m"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl openssl iptables ufw >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl openssl iptables-services >/dev/null 2>&1
    fi
}

# --- 部署函数 ---
deploy_hy2() {
    check_deps

    RAND_PORT=$((20000 + RANDOM % 20000))
    RAND_PASS=$(openssl rand -hex 8)
    
    read -p "请输入端口 (默认 $RAND_PORT): " P
    P=${P:-$RAND_PORT}
    read -p "请输入密码 (默认 $RAND_PASS): " PASS
    PASS=${PASS:-$RAND_PASS}
    read -p "请输入伪装 SNI 域名 (默认 bing.com): " SNI
    SNI=${SNI:-bing.com}

    echo -e "\n\e[36m[1/5] 正在从官方获取 Hysteria2 核心...\e[0m"
    bash <(curl -fsSL https://get.hy2.sh/)
    
    echo -e "\e[36m[2/5] 正在创建配置目录...\e[0m"
    mkdir -p /etc/hysteria
    
    echo -e "\e[36m[3/5] 正在生成自签名 TLS 证书 (SNI: $SNI)...\e[0m"
    openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/server.key 2>/dev/null
    openssl req -new -x509 -days 36500 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=$SNI" 2>/dev/null
    
    echo -e "\e[36m[4/5] 正在写入全平台兼容配置文件...\e[0m"
    cat <<EOF > /etc/hysteria/config.yaml
listen: :$P
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $PASS
masquerade:
  type: status
  status:
    code: 404
ignoreClientBandwidth: true
EOF
    
    echo -e "\e[36m[5/5] 放行 UDP 端口并配置开机自启机制...\e[0m"
    # 自动放行防火墙并进行持久化保存
    iptables -I INPUT -p udp --dport $P -j ACCEPT 2>/dev/null
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || service iptables save 2>/dev/null || true
    ufw allow $P/udp 2>/dev/null
    
    # 赋予系统用户权限
    chmod 644 /etc/hysteria/server.crt
    chmod 600 /etc/hysteria/server.key
    chown -R hysteria:hysteria /etc/hysteria/ 2>/dev/null || true
    
    # 开机自启守护
    systemctl enable hysteria-server.service
    systemctl restart hysteria-server.service
    
    IP=$(curl -4s ipv4.icanhazip.com || curl -4s ip.sb || curl -4s api.ipify.org)
    LOC=$(curl -s http://ip-api.com/line/?fields=countryCode)
    [ -z "$LOC" ] && LOC="VPS"
    
    # 导出完美兼容 v2rayN、OpenClash 与 Subconverter 的节点 URL
    URI="hysteria2://$PASS@$IP:$P/?insecure=1&sni=$SNI#${LOC}_HY2"
    echo "$URI" > /etc/hysteria/share_link.txt
    
    echo -e "\n\e[32m====================================================\e[0m"
    echo -e "\e[32m 部署完成！服务已就绪，开机自启与 UDP 防火墙规则已写入。\e[0m"
    echo -e "\e[32m====================================================\e[0m"
    echo -e "\e[33m节点链接 (可直接导入 v2rayN 或粘贴至订阅转换): \e[0m"
    echo -e "$URI"
    echo -e "\e[32m====================================================\e[0m"
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# --- BBR 加速中心 ---
set_bbr() {
    echo -e "\e[36m正在优化 BBR 网络加速策略...\e[0m"
    
    # 清理旧的重复写入项，防止 /etc/sysctl.conf 冗余堆叠
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    
    read -p "请选择队列算法 (1: FQ [推荐], 2: CAKE): " bbr_choice
    if [ "$bbr_choice" == "2" ]; then
        echo "net.core.default_qdisc=cake" >> /etc/sysctl.conf
    else
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    fi
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    
    sysctl -p >/dev/null 2>&1
    echo -e "\e[32mBBR 加速配置已成功应用并生效！\e[0m"
    read -n 1 -s -r -p "按任意键返回..."
}

# --- 主循环控制 ---
while true; do
    clear
    echo "===================================================="
    echo "       HY2 一键管理工具 (Ultimate Progress Version) "
    echo "       本项目链接：https://github.com/yuan1228/hy2"
    echo "                            （由AI制作仅供学习参考）"
    echo "                                         by yuan1228"
    echo "===================================================="
    echo " 1. 一键安装 / 覆盖配置"
    echo " 2. 查看节点链接"
    echo " 3. 安装原版BBR(FQ/CAKE)"
    echo " 4. 查看运行日志"
    echo " 5. 彻底卸载"
    echo " 0. 退出"
    echo "===================================================="
    read -p "指令 [0-5]: " choice
    case $choice in
        1) deploy_hy2 ;;
        2) 
            echo -e "\n\e[33m当前保存的节点链接：\e[0m"
            cat /etc/hysteria/share_link.txt 2>/dev/null || echo "暂未配置节点"
            echo
            read -n 1 -s -r -p "按任意键返回..." 
            ;;
        3) set_bbr ;;
        4) 
            journalctl -u hysteria-server -n 50 --no-pager --output cat
            echo
            read -n 1 -s -r -p "按任意键返回..." 
            ;;
        5) 
            systemctl stop hysteria-server 2>/dev/null
            systemctl disable hysteria-server 2>/dev/null
            rm -rf /etc/hysteria/ /usr/bin/hysteria /usr/local/bin/hysteria /usr/local/bin/yuan /etc/systemd/system/hysteria-server.service
            systemctl daemon-reload
            echo -e "\e[32m服务及关联文件已彻底清理卸载！\e[0m"
            sleep 1 
            exit 0
            ;;
        0) exit 0 ;;
    esac
done
