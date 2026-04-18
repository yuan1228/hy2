#!/bin/bash

# 等待1秒, 避免curl下载脚本的打印吞掉提示信息
sleep 1

# --- 颜色与UI定义 ---
red='\e[91m'
green='\e[92m'
yellow='\e[93m'
magenta='\e[95m'
cyan='\e[96m'
none='\e[0m'

echo -e "${cyan}  _   _           _            _       ___  ${none}"
echo -e "${cyan} | | | |_   _ ___| |_ ___ _ __(_)__ _ |__ \ ${none}"
echo -e "${cyan} | |_| | | | / __| __/ _ \ '__| / _\` |  / / ${none}"
echo -e "${cyan} |  _  | |_| \__ \ ||  __/ |  | \ (_| | / /_ ${none}"
echo -e "${cyan} |_| |_|\__, |___/\__\___|_|  |_|\__,_|/____|${none}"
echo -e "${cyan}        |___/  袁先生专属·高阶抗封锁版        ${none}\n"

# --- 全局快捷入口注入 ---
install_shortcut() {
    SCRIPT_PATH=$(readlink -f "$0")
    if [ "$SCRIPT_PATH" != "/usr/local/bin/yuan" ]; then
        cp "$SCRIPT_PATH" /usr/local/bin/yuan
        chmod +x /usr/local/bin/yuan
        echo -e "${green}✅ 全局快捷命令 'yuan' 已自动安装！以后随时输入 yuan 即可呼出本面板。${none}\n"
        sleep 1
    fi
}

# --- 核心逻辑：安装与配置 ---
install_hy2() {
    echo -e "${yellow}>>> 1. 环境准备与依赖安装...${none}"
    apt-get update -qq
    apt-get -y install curl wget openssl qrencode net-tools lsof -qq

    echo -e "\n${yellow}>>> 2. 网络探测与 IP 获取...${none}"
    InFaces=($(ls /sys/class/net/ | grep -E '^(eth|ens|eno|esp|enp|venet|vif)'))
    for i in "${InFaces[@]}"; do
        Public_IPv4=$(curl -4s --interface "$i" -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")
        Public_IPv6=$(curl -6s --interface "$i" -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")
        [[ -n "$Public_IPv4" ]] && IPv4="$Public_IPv4"
        [[ -n "$Public_IPv6" ]] && IPv6="$Public_IPv6"
    done

    # 交互：网络栈选择 (融合开源脚本逻辑)
    if [[ -n "$IPv4" && -n "$IPv6" ]]; then
        echo -e "你的服务器是 ${magenta}双栈网络${none}，请选择将 Hy2 绑定在哪个 IP 上："
        read -p "$(echo -e "输入 ${cyan}4${none} 选 IPv4, 输入 ${cyan}6${none} 选 IPv6 (默认 4): ")" netstack
        if [[ $netstack == "6" ]]; then
            ip=${IPv6}
            is_ipv6=true
        else
            ip=${IPv4}
            is_ipv6=false
        fi
    else
        ip=${IPv4:-$IPv6}
        [[ "$ip" == "$IPv6" ]] && is_ipv6=true || is_ipv6=false
    fi

    echo -e "👉 当前绑定 IP: ${cyan}${ip}${none}\n"

    # 交互：自定义参数
    # 生成基于硬件的固定密码，重装不丢失
    uuidSeed=${IPv4}${IPv6}$(cat /proc/sys/kernel/hostname)$(timedatectl | awk '/Time zone/ {print $3}')
    default_uuid=$(curl -sL https://www.uuidtools.com/api/generate/v3/namespace/ns:dns/name/${uuidSeed} | grep -oP '[^-]{8}-[^-]{4}-[^-]{4}-[^-]{4}-[^-]{12}')
    
    read -p "$(echo -e "👉 请输入 ${yellow}端口${none} [1-65535] (默认 ${cyan}45678${none}): ")" port
    port=${port:-45678}

    read -p "$(echo -e "👉 请输入 ${yellow}连接密码${none} (默认使用本机固定硬件ID ${cyan}${default_uuid}${none}): ")" pwd
    pwd=${pwd:-$default_uuid}

    read -p "$(echo -e "👉 请输入 ${yellow}Salamander混淆密码${none} (防封锁核心, 默认随机): ")" obfs_pwd
    [ -z "$obfs_pwd" ] && obfs_pwd=$(tr -dc a-z0-9 </dev/urandom | head -c 8)

    read -p "$(echo -e "👉 请输入 ${yellow}伪装域名 SNI${none} (默认 ${cyan}aws.amazon.com${none}): ")" domain
    domain=${domain:-aws.amazon.com}

    echo -e "\n${yellow}>>> 3. 执行 Hy2 官方一键安装...${none}"
    bash <(curl -fsSL https://get.hy2.sh/)

    echo -e "\n${yellow}>>> 4. 生成高阶 ECDSA 证书与 pinSHA256...${none}"
    cert_dir="/etc/ssl/private/hysteria"
    mkdir -p ${cert_dir}
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "${cert_dir}/${domain}.key" -out "${cert_dir}/${domain}.crt" \
        -subj "/CN=${domain}" -days 36500 2>/dev/null
    chmod -R 777 ${cert_dir}
    pinsha256_cert=$(openssl x509 -in "${cert_dir}/${domain}.crt" -outform DER | sha256sum | awk '{print $1}')

    echo -e "${yellow}>>> 5. 写入强效抗封锁配置文件...${none}"
    cat >/etc/hysteria/config.yaml <<-EOF
listen: :${port}
tls:
  cert: ${cert_dir}/${domain}.crt
  key: ${cert_dir}/${domain}.key
auth:
  type: password
  password: ${pwd}
obfs:
  type: salamander
  password: ${obfs_pwd}
masquerade:
  type: proxy
  proxy:
    url: https://${domain}
    rewriteHost: true
ignoreClientBandwidth: true
EOF

    echo -e "${yellow}>>> 6. 重启服务...${none}"
    systemctl daemon-reload
    systemctl enable hysteria-server.service >/dev/null 2>&1
    systemctl restart hysteria-server.service

    # 生成链接
    if [ "$is_ipv6" = true ]; then format_ip="[${ip}]"; else format_ip="${ip}"; fi
    hy2_url="hysteria2://${pwd}@${format_ip}:${port}?sni=${domain}&obfs=salamander&obfs-password=${obfs_pwd}&pinSHA256=${pinsha256_cert}#Hy2-Pro-${port}"
    
    echo "$hy2_url" > /etc/hysteria/share_link.txt

    show_node_info "$ip" "$port" "$pwd" "$obfs_pwd" "$domain" "$pinsha256_cert" "$hy2_url"
}

# --- 展示节点信息 ---
show_node_info() {
    clear
    echo -e "${cyan}======================================================${none}"
    echo -e "${green}             ✅ Hysteria2 高阶节点部署成功！          ${none}"
    echo -e "${cyan}======================================================${none}"
    echo -e "📍 ${yellow}服务器 IP${none}      : $1"
    echo -e "🔌 ${yellow}UDP 端口${none}       : $2"
    echo -e "🔑 ${yellow}连接密码${none}       : $3"
    echo -e "👻 ${yellow}混淆密码(obfs)${none} : $4"
    echo -e "🛡️  ${yellow}SNI 伪装域名${none}   : $5"
    echo -e "🔒 ${yellow}证书指纹(PIN)${none}  : $6"
    echo -e "${cyan}======================================================${none}"
    echo -e "🔗 ${green}节点链接 (推荐直接复制以下完整链接):${none}"
    echo -e "${magenta}$7${none}"
    echo -e "${cyan}======================================================${none}"
    qrencode -t ANSIUTF8 "$7"
    echo -e "${cyan}======================================================${none}"
    echo -e "⚠️  ${red}防呆提醒${none}: 必须在云防火墙放行 UDP $2 端口！"
    echo -e "⚠️  ${red}快捷提醒${none}: 终端输入 ${green}yuan${none} 即可随时打开本菜单。"
    
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# --- 深度卸载模块 ---
uninstall_hy2() {
    clear
    echo -e "${red}>>> 正在彻底物理拔除 Hysteria2...${none}"
    systemctl stop hysteria-server 2>/dev/null
    systemctl disable hysteria-server 2>/dev/null
    rm -f /etc/systemd/system/hysteria-server.service
    rm -f /usr/local/bin/hysteria
    rm -rf /etc/hysteria/
    rm -rf /etc/ssl/private/hysteria/
    systemctl daemon-reload
    echo -e "${green}✅ Hysteria2 已彻底卸载！${none}"
    sleep 2
}

uninstall_3xui() {
    clear
    echo -e "${red}>>> 正在彻底抹除 3x-ui 面板...${none}"
    systemctl stop x-ui 2>/dev/null
    systemctl disable x-ui 2>/dev/null
    rm -f /etc/systemd/system/x-ui.service
    rm -rf /usr/local/x-ui/
    rm -rf /etc/x-ui/
    rm -f /usr/bin/x-ui
    systemctl daemon-reload
    echo -e "${green}✅ 3x-ui 面板及其所有数据库已物理销毁！${none}"
    sleep 2
}

# --- 主菜单 ---
install_shortcut

while true; do
    clear
    echo -e "${cyan}======================================================${none}"
    echo -e "${green}         袁先生的专属网络枢纽 (快捷键: yuan)          ${none}"
    echo -e "${cyan}======================================================${none}"
    echo -e " ${yellow}1.${none} 🚀 安装或重置 Hysteria2 (官方核心+抗封锁配置)"
    echo -e " ${yellow}2.${none} 👁️  查看当前 Hy2 节点链接与二维码"
    echo -e " ${yellow}3.${none} 🗑️  深度卸载 Hysteria2"
    echo -e " ${yellow}4.${none} 🗑️  深度卸载 3x-ui 面板"
    echo -e " ${yellow}0.${none} 🚪 退出脚本"
    echo -e "${cyan}======================================================${none}"
    read -p "$(echo -e "👉 请输入数字选择 [0-4]: ")" choice

    case $choice in
        1) install_hy2 ;;
        2) 
            if [ -f "/etc/hysteria/share_link.txt" ]; then
                clear
                link=$(cat /etc/hysteria/share_link.txt)
                echo -e "${green}🔗 历史节点链接:${none}\n${magenta}$link${none}\n"
                qrencode -t ANSIUTF8 "$link"
                read -n 1 -s -r -p "按任意键返回主菜单..."
            else
                echo -e "\n${red}未检测到安装记录，请先执行安装！${none}"
                sleep 2
            fi
            ;;
        3) uninstall_hy2 ;;
        4) uninstall_3xui ;;
        0) clear; exit 0 ;;
        *) echo -e "\n${red}输入错误!${none}"; sleep 1 ;;
    esac
done
