#!/bin/bash
# ============================================================
# Yuan VPS 工具箱 · 协议模块：Hysteria2
# 官方核心 + 自签证书 + salamander 混淆 + 伪装回源
# ============================================================

HY2_ID="hy2"
HY2_NAME="Hysteria2"
HY2_DESC="UDP 高速协议，弱网/高丢包表现最好"
HY2_DIR="$YUAN_CONF/hy2"
HY2_BIN="/usr/local/bin/hysteria"
HY2_SVC="hysteria-server.service"
HY2_LINK="$HY2_DIR/link.txt"
# 兼容 v1 旧路径
HY2_LEGACY_LINK="/etc/hysteria/share_link.txt"

hy2_installed() { [[ -x "$HY2_BIN" && -f "$HY2_DIR/config.yaml" ]]; }
hy2_active()    { svc_active "$HY2_SVC"; }
hy2_port() {
    grep -E '^listen:' "$HY2_DIR/config.yaml" 2>/dev/null \
        | grep -oE '[0-9]+' | head -1
}

# 从旧分享链接解析配置（覆盖安装时做默认值；兼容 v1 路径）
hy2_load_old() {
    HY2_OLD_PORT=""; HY2_OLD_PASS=""; HY2_OLD_SNI=""; HY2_OLD_OBFS=""
    local link=""
    [[ -f "$HY2_LINK" ]] && link="$(cat "$HY2_LINK")"
    [[ -z "$link" && -f "$HY2_LEGACY_LINK" ]] && link="$(cat "$HY2_LEGACY_LINK")"
    [[ -z "$link" ]] && return 0
    HY2_OLD_PASS="$(printf '%s' "$link" | sed -n 's|^hysteria2://\([^@]*\)@.*|\1|p')"
    HY2_OLD_PORT="$(printf '%s' "$link" | sed -n 's|^hysteria2://[^@]*@[^:]*:\([0-9]\{1,5\}\)/?.*|\1|p')"
    HY2_OLD_SNI="$(printf '%s' "$link" | sed -n 's|.*[?&]sni=\([^&#]*\).*|\1|p')"
    HY2_OLD_OBFS="$(printf '%s' "$link" | sed -n 's|.*[?&]obfs-password=\([^&#]*\).*|\1|p')"
    HY2_OLD_PASS="$(urldecode "$HY2_OLD_PASS")"
    HY2_OLD_OBFS="$(urldecode "$HY2_OLD_OBFS")"
}

hy2_deploy() {
    hy2_load_old
    local port pass sni obfs ip cc uri

    bold "—— 部署 Hysteria2 ——"
    echo
    ask_port "监听 UDP 端口" "${HY2_OLD_PORT:-$((40000 + RANDOM % 10000))}" port
    ask_secret "认证密码" "${HY2_OLD_PASS:-$(gen_hex 16)}" pass
    ask_input "伪装域名 (SNI)" "${HY2_OLD_SNI:-www.cloudflare.com}" sni
    [[ -z "${HY2_OLD_OBFS:-}" ]] && HY2_OLD_OBFS="$(gen_hex 8)"
    obfs="$HY2_OLD_OBFS"

    step "[1/6] 安装 Hysteria2 官方核心…"
    ensure_cmd curl curl
    if ! bash <(curl -fsSL --max-time 60 https://get.hy2.sh/); then
        err "官方安装脚本执行失败，请检查网络后重试"
        echo; pause; return 1
    fi
    [[ -x "$HY2_BIN" ]] || { err "未找到 hysteria 可执行文件"; echo; pause; return 1; }

    step "[2/6] 准备配置目录…"
    ensure_dir "$HY2_DIR"

    step "[3/6] 生成自签 TLS 证书 (CN=$sni)…"
    ensure_cmd openssl openssl
    rm -f "$HY2_DIR/server.key" "$HY2_DIR/server.crt"
    openssl ecparam -genkey -name prime256v1 -out "$HY2_DIR/server.key" 2>/dev/null
    openssl req -new -x509 -days 36500 -key "$HY2_DIR/server.key" \
        -out "$HY2_DIR/server.crt" -subj "/CN=$sni" 2>/dev/null
    if [[ ! -s "$HY2_DIR/server.key" || ! -s "$HY2_DIR/server.crt" ]]; then
        err "证书生成失败"; echo; pause; return 1
    fi

    step "[4/6] 写入配置文件…"
    cat > "$HY2_DIR/config.yaml" <<EOF
listen: :$port

tls:
  cert: $HY2_DIR/server.crt
  key: $HY2_DIR/server.key

auth:
  type: password
  password: $pass

obfs:
  type: salamander
  salamander:
    password: $obfs

masquerade:
  type: proxy
  proxy:
    url: https://$sni
    rewriteHost: true

ignoreClientBandwidth: true
EOF
    chmod 600 "$HY2_DIR/config.yaml" "$HY2_DIR/server.key"
    chmod 644 "$HY2_DIR/server.crt"

    step "[5/6] 启动服务并设置开机自启…"
    if ! svc_restart "$HY2_SVC"; then
        err "服务启动失败，请查看运行日志排查"
        echo; pause; return 1
    fi

    step "[6/6] 生成分享链接…"
    ip="$(get_pubip)"
    if [[ -z "$ip" ]]; then
        warn "未能自动获取公网 IP"
        ask_input "请手动输入公网 IP（v6 请带括号，如 [2a01::1]）" "" ip
        [[ -z "$ip" ]] && { err "未提供 IP，部署中止"; echo; pause; return 1; }
    fi
    cc="$(geo_cc)"; [[ -z "$cc" ]] && cc="VPS"
    uri="hysteria2://$(urlencode "$pass")@${ip}:${port}/?insecure=1&sni=$(urlencode "$sni")&obfs=salamander&obfs-password=$(urlencode "$obfs")#${cc}_HY2"
    printf '%s\n' "$uri" > "$HY2_LINK"
    chmod 600 "$HY2_LINK"

    # 同步放行防火墙
    fw_allow "$port" udp 2>/dev/null || true

    echo
    ok "部署完成！服务运行中，开机自启已设置"
    warn "节点链接：$uri"
    dim  "链接已保存至 $HY2_LINK（权限 600）"
    echo
    pause
}

hy2_link() {
    if [[ -f "$HY2_LINK" ]]; then
        cat "$HY2_LINK"; echo
    elif [[ -f "$HY2_LEGACY_LINK" ]]; then
        cat "$HY2_LEGACY_LINK"; echo
    else
        warn "暂无节点链接，请先部署"
        echo
    fi
    pause
}

hy2_restart() {
    step "正在重启 Hysteria2…"
    if svc_restart "$HY2_SVC"; then ok "重启成功，服务运行正常"
    else err "重启失败，请查看运行日志"; fi
    echo; pause
}

hy2_logs() {
    info "最近 60 行日志（下方实时跟踪，Ctrl+C 停止）"
    echo
    journalctl -u "$HY2_SVC" -n 60 --no-pager
    echo
    journalctl -u "$HY2_SVC" -f --output cat
}

hy2_uninstall() {
    confirm "确定彻底卸载 Hysteria2 吗？配置与证书将全部删除" || return 0
    step "停止并禁用服务…"
    systemctl stop "$HY2_SVC" 2>/dev/null
    systemctl disable "$HY2_SVC" 2>/dev/null
    rm -f /etc/systemd/system/hysteria-server.service
    rm -rf /etc/systemd/system/hysteria-server.service.d
    systemctl daemon-reload 2>/dev/null
    step "删除程序与配置…"
    rm -rf "$HY2_DIR" "$HY2_BIN" "$HY2_LEGACY_LINK"
    rmdir /etc/hysteria 2>/dev/null || true
    ok "Hysteria2 已彻底卸载"
    echo; pause
}

hy2_status() {
    bold "—— Hysteria2 状态 ——"
    echo
    if hy2_installed; then
        echo -e "安装状态：${C_GRN}已安装${C_RST}"
    else
        err "未安装"; echo; pause; return 0
    fi
    if hy2_active; then ok "服务状态：运行中 (active)"
    else err "服务状态：未运行"; fi
    echo "开机自启：$(svc_enabled "$HY2_SVC" && echo 是 || echo 否)"
    echo "监听端口：$(hy2_port) (UDP)"
    echo "核心版本：$("$HY2_BIN" version 2>/dev/null | head -1)"
    echo
    pause
}
