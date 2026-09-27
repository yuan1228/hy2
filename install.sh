#!/bin/bash
# ====================================================
# HY2 一键管理工具
# 专为 Linux VPS 设计的 Hysteria2 部署与管理工具
# 项目地址：https://github.com/yuan1228/hy2
# ====================================================

# --- 基础检查：必须以 root 运行 ---
if [ "$EUID" -ne 0 ]; then
    echo "错误：请使用 root 用户运行此脚本。"
    exit 1
fi

REMOTE_URL="https://raw.githubusercontent.com/yuan1228/hy2/refs/heads/main/install.sh"
YUAN_BIN="/usr/local/bin/yuan"
CONF_DIR="/etc/hysteria"
SERVICE="hysteria-server.service"
HY_BIN="/usr/local/bin/hysteria"

# --- 输出样式 ---
info()  { echo -e "\e[36m$*\e[0m"; }
ok()    { echo -e "\e[32m$*\e[0m"; }
warn()  { echo -e "\e[33m$*\e[0m"; }
err()   { echo -e "\e[31m$*\e[0m"; }
pause() { read -n 1 -s -r -p "按任意键返回..."; echo; }

# --- 从远程拉取脚本，返回临时文件路径 ---
fetch_remote() {
    local tmp
    tmp=$(mktemp)
    if curl -fsSL --max-time 30 "$REMOTE_URL" -o "$tmp" && [ -s "$tmp" ]; then
        printf '%s' "$tmp"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# --- yuan 快捷指令：安装 / 自动更新 ---
# 修复：首装时 $0 为 bash 不可用，改为直接从远程拉取安装；
#       更新时 curl 加 -f，避免 404 页面覆盖正常文件。
if [ ! -f "$YUAN_BIN" ]; then
    if tmp=$(fetch_remote); then
        mv "$tmp" "$YUAN_BIN"
        chmod +x "$YUAN_BIN"
    else
        warn "警告：yuan 快捷指令安装失败，网络恢复后可重新运行安装命令补装。"
    fi
elif [ "$1" != "--no-update" ]; then
    if tmp=$(fetch_remote); then
        if ! cmp -s "$tmp" "$YUAN_BIN"; then
            mv "$tmp" "$YUAN_BIN"
            chmod +x "$YUAN_BIN"
            echo "检测到新版本，已更新。请重新输入 yuan 进入。"
            exit 0
        fi
        rm -f "$tmp"
    fi
fi

# --- URL 编解码：保证密码中的特殊字符不破坏分享链接 ---
urlencode() {
    local s="$1" out="" c hex i
    for (( i=0; i<${#s}; i++ )); do
        c="${s:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) out+="$c" ;;
            *) printf -v hex '%%%02X' "'$c"; out+="$hex" ;;
        esac
    done
    printf '%s' "$out"
}

urldecode() {
    local s="$1"
    printf '%b' "$(printf '%s' "$s" | sed -E 's/%([0-9A-Fa-f]{2})/\\x\1/g')"
}

# --- 从已有分享链接解析旧配置，覆盖安装时用作默认值 ---
load_old_config() {
    OLD_PORT=""; OLD_PASS=""; OLD_SNI=""; OLD_OBFS=""
    local link
    link=$(cat "$CONF_DIR/share_link.txt" 2>/dev/null) || return 0
    [ -z "$link" ] && return 0
    OLD_PASS=$(printf '%s' "$link" | sed -n 's|^hysteria2://\([^@]*\)@.*|\1|p')
    OLD_PORT=$(printf '%s' "$link" | sed -n 's|^hysteria2://[^@]*@[^:]*:\([0-9]\{1,5\}\)/?.*|\1|p')
    OLD_SNI=$(printf '%s' "$link" | sed -n 's|.*[?&]sni=\([^&#]*\).*|\1|p')
    OLD_OBFS=$(printf '%s' "$link" | sed -n 's|.*[?&]obfs-password=\([^&#]*\).*|\1|p')
}

# --- 部署函数 ---
deploy_hy2() {
    load_old_config
    local DEF_PORT DEF_PASS DEF_SNI P PASS SNI OBFS_PASS IP LOC URI

    DEF_PORT=${OLD_PORT:-$((40000 + RANDOM % 10000))}
    DEF_PASS=$(urldecode "${OLD_PASS:-$(openssl rand -hex 8)}")
    DEF_SNI=${OLD_SNI:-aws.amazon.com}

    read -p "请输入端口 (默认 $DEF_PORT): " P
    P=${P:-$DEF_PORT}
    # 修复：端口合法性校验
    if ! [[ "$P" =~ ^[0-9]+$ ]] || [ "$P" -lt 1 ] || [ "$P" -gt 65535 ]; then
        err "端口不合法：$P，请输入 1-65535 的数字。"
        echo; pause; return 1
    fi
    if ss -tuln 2>/dev/null | grep -qE "[:.]$P([[:space:]]|\$)"; then
        warn "警告：端口 $P 疑似已被占用，继续可能导致启动失败。"
        read -p "仍要继续吗？(y/N): " yn
        if [ "$yn" != "y" ] && [ "$yn" != "Y" ]; then return 1; fi
    fi

    read -p "请输入密码 (默认 $DEF_PASS): " PASS
    PASS=${PASS:-$DEF_PASS}
    read -p "请输入伪装域名 (默认 $DEF_SNI): " SNI
    SNI=${SNI:-$DEF_SNI}

    info "\n[1/6] 正在从官方获取 Hysteria2 核心..."
    # 修复：检查官方安装脚本是否成功、二进制是否存在，失败直接中止
    if ! bash <(curl -fsSL https://get.hy2.sh/); then
        err "官方安装脚本执行失败，请检查网络后重试。"
        echo; pause; return 1
    fi
    if [ ! -x "$HY_BIN" ]; then
        err "未找到 hysteria 可执行文件，安装失败。"
        echo; pause; return 1
    fi

    info "[2/6] 正在创建配置目录..."
    mkdir -p "$CONF_DIR"
    chmod 700 "$CONF_DIR"

    info "[3/6] 正在生成自签名 TLS 证书 (SNI: $SNI)..."
    rm -f "$CONF_DIR/server.key" "$CONF_DIR/server.crt"
    openssl ecparam -genkey -name prime256v1 -out "$CONF_DIR/server.key" 2>/dev/null
    openssl req -new -x509 -days 36500 -key "$CONF_DIR/server.key" \
        -out "$CONF_DIR/server.crt" -subj "/CN=$SNI" 2>/dev/null
    # 修复：证书生成失败不再静默吞掉
    if [ ! -s "$CONF_DIR/server.key" ] || [ ! -s "$CONF_DIR/server.crt" ]; then
        err "证书生成失败，请确认已安装 openssl。"
        echo; pause; return 1
    fi

    info "[4/6] 正在写入配置文件..."
    OBFS_PASS=$(urldecode "${OLD_OBFS:-$(openssl rand -hex 6)}")
    cat > "$CONF_DIR/config.yaml" <<EOF
listen: :$P
tls:
  cert: $CONF_DIR/server.crt
  key: $CONF_DIR/server.key
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
    # 修复：含密码的配置文件收紧权限
    chmod 600 "$CONF_DIR/config.yaml" "$CONF_DIR/server.key"
    chmod 644 "$CONF_DIR/server.crt"
    chown -R hysteria:hysteria "$CONF_DIR" 2>/dev/null || true

    info "[5/6] 正在设置开机自启并启动服务..."
    systemctl daemon-reload 2>/dev/null
    systemctl enable "$SERVICE" 2>/dev/null
    # 修复：覆盖安装时必须 restart 才能加载新配置；启动后验证服务真的活着
    if ! systemctl restart "$SERVICE" 2>/dev/null; then
        err "服务启动失败，请选择「查看运行日志」排查。"
        echo; pause; return 1
    fi
    sleep 2
    if ! systemctl is-active --quiet "$SERVICE"; then
        err "服务未能保持运行，最新日志："
        journalctl -u "$SERVICE" -n 20 --no-pager
        echo; pause; return 1
    fi

    info "[6/6] 正在生成节点分享链接..."
    IP=$(curl -4s --max-time 8 ipv4.icanhazip.com \
        || curl -4s --max-time 8 ip.sb \
        || curl -4s --max-time 8 ifconfig.me)
    # 修复：自动获取失败时让用户手动输入，不再生成空 IP 链接
    if [ -z "$IP" ]; then
        warn "未能自动获取公网 IP。"
        read -p "请手动输入本机公网 IP: " IP
    fi
    LOC=$(curl -s --max-time 8 "http://ip-api.com/line/?fields=countryCode" 2>/dev/null)
    [ -z "$LOC" ] && LOC="VPS"
    URI="hysteria2://$(urlencode "$PASS")@$IP:$P/?insecure=1&sni=$SNI&obfs=salamander&obfs-password=$(urlencode "$OBFS_PASS")#${LOC}_HY2"
    echo "$URI" > "$CONF_DIR/share_link.txt"
    chmod 600 "$CONF_DIR/share_link.txt"

    echo
    ok "部署完成！开机自启已设置，服务运行正常。"
    warn "节点链接： $URI"
    echo
    pause
}

# --- 查看服务状态（新增） ---
show_status() {
    info "===== 服务状态 ====="
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
        ok "运行中 (active)"
    else
        err "未运行 (inactive)"
    fi
    echo "开机自启：$(systemctl is-enabled "$SERVICE" 2>/dev/null || echo unknown)"
    echo "监听端口："
    ss -tulnp 2>/dev/null | grep -i hysteria | sed 's/^/  /' || echo "  (未检测到监听端口)"
    echo "核心版本："
    "$HY_BIN" version 2>/dev/null | head -3 | sed 's/^/  /' || echo "  (未安装)"
    echo
    pause
}

# --- 重启服务（新增） ---
restart_service() {
    info "正在重启 hysteria 服务..."
    if systemctl restart "$SERVICE" 2>/dev/null && systemctl is-active --quiet "$SERVICE"; then
        ok "重启成功，服务运行正常。"
    else
        err "重启后服务未运行，请选择「查看运行日志」排查。"
    fi
    echo
    pause
}

# --- 加速中心 ---
set_bbr() {
    info "正在检查内核加速条件..."
    # 修复：容器虚拟化下 BBR 通常无法生效，提前警告
    local virt
    virt=$(systemd-detect-virt 2>/dev/null || echo "none")
    if [ "$virt" = "openvz" ] || [ "$virt" = "lxc" ]; then
        warn "检测到容器虚拟化 ($virt)，通常无法修改内核拥塞算法，配置可能不会生效。"
    fi
    # 修复：内核不支持 BBR 时直接取消，不再写无效配置
    if ! sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
        err "当前内核不支持 BBR，已取消。"
        echo; pause; return 1
    fi

    # 先清理旧配置，防止文件无限重复追加（锚定行首，避免误删注释）
    sed -i '/^net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/^net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

    read -p "请选择队列算法 (1: FQ [推荐], 2: CAKE): " bbr_choice
    if [ "$bbr_choice" = "2" ]; then
        # 修复：CAKE 模块缺失时回退到 FQ
        if ! modprobe sch_cake 2>/dev/null && [ ! -d "/sys/module/sch_cake" ]; then
            warn "未找到 sch_cake 模块，已自动改用 FQ。"
            echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        else
            echo "net.core.default_qdisc=cake" >> /etc/sysctl.conf
        fi
    else
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    fi
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

    sysctl -p >/dev/null 2>&1
    echo "当前拥塞算法：$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    ok "BBR 加速配置已写入并生效！"
    echo
    pause
}

# --- 查看运行日志 ---
show_logs() {
    info "最近 80 行日志（下方实时跟踪，按 Ctrl+C 停止）..."
    echo
    journalctl -u "$SERVICE" -n 80 --no-pager
    echo
    journalctl -u "$SERVICE" -f --output cat
}

# --- 卸载 ---
uninstall_hy2() {
    read -p "确定要彻底卸载 Hysteria2 吗？(y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then return 0; fi

    info "正在停止并禁用服务..."
    systemctl stop "$SERVICE" 2>/dev/null
    systemctl disable "$SERVICE" 2>/dev/null
    # 修复：同时删除官方安装脚本留下的 unit 文件
    rm -f /etc/systemd/system/hysteria-server.service
    rm -rf /etc/systemd/system/hysteria-server.service.d
    systemctl daemon-reload 2>/dev/null

    info "正在删除程序与配置文件..."
    rm -rf "$CONF_DIR" "$HY_BIN"

    info "正在清理 sysctl 加速配置..."
    # 修复：卸载时清理本工具写入的 BBR 配置
    sed -i '/^net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/^net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1 || true

    # 修复：脚本可能正由 yuan 自身运行，退出时再删除，避免执行中途文件消失
    if [ -f "$YUAN_BIN" ]; then
        trap 'rm -f "$YUAN_BIN"' EXIT
    fi
    ok "已彻底卸载！"
    sleep 1
    exit 0
}

# --- 主循环 ---
while true; do
    clear
    echo "===================================================="
    echo "       HY2 一键管理工具"
    echo "       项目地址：https://github.com/yuan1228/hy2"
    echo "                     （由AI制作仅供学习参考）"
    echo "                                  by yuan1228"
    echo "===================================================="
    echo " 1. 一键安装 / 覆盖配置"
    echo " 2. 查看节点链接"
    echo " 3. 安装原版BBR(FQ/CAKE)"
    echo " 4. 查看运行日志"
    echo " 5. 查看服务状态"
    echo " 6. 重启服务"
    echo " 7. 卸载"
    echo " 0. 退出"
    echo "===================================================="
    read -p "指令 [0-7]: " choice
    case $choice in
        1) deploy_hy2 ;;
        2) cat "$CONF_DIR/share_link.txt" 2>/dev/null || echo "暂无配置，请先执行安装"; echo; pause ;;
        3) set_bbr ;;
        4) show_logs ;;
        5) show_status ;;
        6) restart_service ;;
        7) uninstall_hy2 ;;
        0) exit 0 ;;
        *) warn "无效指令"; sleep 1 ;;
    esac
done
