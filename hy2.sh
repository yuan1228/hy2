#!/bin/bash

# 定义颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # 恢复默认

install_hy2() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}              开始部署 Hysteria2 抗封锁节点             ${NC}"
    echo -e "${CYAN}======================================================${NC}"

    # 1. 交互式获取端口
    read -p "👉 请输入自定义 UDP 端口 (直接回车则默认使用 45678): " INPUT_PORT
    PORT=${INPUT_PORT:-45678}

    echo -e "\n${YELLOW}>>> 正在初始化环境并安装依赖...${NC}"
    apt update -y > /dev/null 2>&1
    apt install -y qrencode curl > /dev/null 2>&1

    # 生成随机参数
    PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    OBFS_PASS=$(tr -dc a-z0-9 </dev/urandom | head -c 8)
    IP=$(curl -s ipv4.icanhazip.com)
    SNI="aws.amazon.com"
    NODE_NAME="Hy2-Pro-${PORT}"

    echo -e "${YELLOW}>>> 正在清理旧容器并生成伪装证书...${NC}"
    docker rm -f hy2 2>/dev/null
    mkdir -p /opt/hy2
    openssl req -x509 -nodes -newkey rsa:2048 \
      -keyout /opt/hy2/server.key -out /opt/hy2/server.crt -days 3650 \
      -subj "/C=US/ST=CA/L=LosAngeles/O=Amazon/OU=AWS/CN=$SNI" 2>/dev/null

    echo -e "${YELLOW}>>> 正在写入核心配置文件...${NC}"
    cat <<EOF > /opt/hy2/config.yaml
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

    echo -e "${YELLOW}>>> 正在拉取并启动 Docker 容器...${NC}"
    docker run -d --name hy2 --restart always \
      --network host \
      -v /opt/hy2:/etc/hysteria \
      tobyxdd/hysteria server -c /etc/hysteria/config.yaml > /dev/null 2>&1

    # 修复了混淆密码的 URI 格式：使用 obfs-password 让所有客户端都能精准识别
    URI="hysteria2://$PASSWORD@$IP:$PORT/?insecure=1&sni=$SNI&obfs=salamander&obfs-password=$OBFS_PASS#$NODE_NAME"

    # 美化输出结果
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
    echo -e "📱 ${YELLOW}扫码导入:${NC}"
    qrencode -t ANSIUTF8 "$URI"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "⚠️  ${RED}致命提醒${NC}: 必须在云服务商防火墙放行 UDP ${PORT} 端口！"
    echo -e "⚠️  ${RED}纠错提醒${NC}: 客户端里的【跳跃端口范围】必须保持为空！"
}

uninstall_hy2() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${RED}               准备卸载 Hysteria2 节点                ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    docker rm -f hy2 2>/dev/null
    rm -rf /opt/hy2
    echo -e "${GREEN}✅ 卸载完成！容器及配置目录已彻底清除。${NC}"
}

# 脚本入口主菜单
clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${GREEN}         Hysteria2 终极管理脚本 (交互式 UI 版)        ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo -e " ${YELLOW}1.${NC} 安装/重置 Hysteria2 节点"
echo -e " ${YELLOW}2.${NC} 一键卸载 Hysteria2 节点"
echo -e " ${YELLOW}0.${NC} 退出脚本"
echo -e "${CYAN}======================================================${NC}"
read -p "👉 请输入数字选择功能 [0-2]: " choice

case $choice in
    1) install_hy2 ;;
    2) uninstall_hy2 ;;
    0) exit 0 ;;
    *) echo -e "${RED}输入错误，已退出。${NC}" ;;
esac
