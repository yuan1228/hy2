#!/bin/bash

# --- 快捷入口安装 ---
if [ ! -f "/usr/local/bin/yuan" ]; then
    cp "$0" /usr/local/bin/yuan
    chmod +x /usr/local/bin/yuan
fi
#!/bin/bash

# --- 自动同步更新逻辑 ---
# 定义远程仓库脚本路径
REMOTE_URL="https://raw.githubusercontent.com/yuan1228/hy2/refs/heads/main/install.sh"

# 如果已安装，先进行静默更新检查
if [ -f "/usr/local/bin/yuan" ]; then
    # 临时下载一份对比
    TMP_FILE=$(mktemp)
    curl -sL "$REMOTE_URL" > "$TMP_FILE"
    # 如果远程文件和本地文件不同，则覆盖更新
    if ! cmp -s "$TMP_FILE" /usr/local/bin/yuan; then
        cp "$TMP_FILE" /usr/local/bin/yuan
        chmod +x /usr/local/bin/yuan
        echo "检测到新版本，已自动同步更新..."
        sleep 1
    fi
    rm -f "$TMP_FILE"
else
    # 首次安装直接拷贝
    cp "$0" /usr/local/bin/yuan
    chmod +x /usr/local/bin/yuan
fi

# --- 主循环界面 ---
while true; do
# ... 后续代码保持不变 ...

# --- 主循环界面 ---
while true; do
    clear
    echo "===================================================="
    echo " 项目地址: https://github.com/yuan1228/hy2"
    echo " 核心架构: H Y S T E R I A  2  M A N A G E R"
    echo "===================================================="
    echo ""
    echo " 1. 安装/重置 Hysteria2"
    echo " 2. 查看节点链接"
    echo " 3. 运行日志"
    echo " 4. BBR加速"
    echo " 5. 升级内核"
    echo " 6. 深度卸载"
    echo " 0. 退出"
    echo ""
    echo "===================================================="
    read -p "指令 [0-6]: " choice
    
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
            echo "安装完成。" && read -n 1 -s -r -p "按任意键..." ;;
        2) cat /etc/hysteria/share_link.txt 2>/dev/null || echo "无配置"; echo; read -n 1 -s -r -p "按任意键..." ;;
        3) journalctl -u hysteria-server -f --output cat ;;
        4) echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf; echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf; sysctl -p; read -n 1 -s -r -p "按任意键..." ;;
        5) bash <(curl -fsSL https://get.hy2.sh/); systemctl restart hysteria-server.service ;;
        6) rm -rf /etc/hysteria/ /usr/local/bin/hysteria; systemctl stop hysteria-server; echo "已卸载"; sleep 1 ;;
        0) exit 0 ;;
    esac
done
