#!/bin/bash
# ============================================================
# Yuan VPS 工具箱 · 协议模块：Trojan（Xray）
# 经典伪装协议，兼容性好，适合与 VLESS 共存做备用
# ============================================================
# shellcheck disable=SC1091
source "$YUAN_ROOT/src/protocols/_xray.sh"

TROJAN_ID="trojan"
TROJAN_NAME="Trojan"
TROJAN_DESC="Xray，经典 TLS 伪装协议"
TROJAN_DIR="$YUAN_CONF/trojan"
TROJAN_SVC="yuan-trojan.service"
TROJAN_LINK="$TROJAN_DIR/link.txt"

trojan_installed() { [[ -f "$TROJAN_DIR/config.json" && -x "$XRAY_BIN" ]]; }
trojan_active()    { svc_active "$TROJAN_SVC"; }
trojan_port() {
    grep -oE '"port":[[:space:]]*[0-9]+' "$TROJAN_DIR/config.json" 2>/dev/null \
        | grep -oE '[0-9]+' | head -1
}

trojan_load_old() {
    TROJAN_OLD_PORT=""; TROJAN_OLD_PASS=""; TROJAN_OLD_SNI=""
    local link=""
    [[ -f "$TROJAN_LINK" ]] && link="$(cat "$TROJAN_LINK")"
    [[ -z "$link" ]] && return 0
    TROJAN_OLD_PASS="$(printf '%s' "$link" | sed -n 's|^trojan://\([^@]*\)@.*|\1|p')"
    TROJAN_OLD_PORT="$(printf '%s' "$link" | sed -n 's|^trojan://[^@]*@[^:]*:\([0-9]\{1,5\}\)?.*|\1|p')"
    TROJAN_OLD_SNI="$(printf '%s' "$link" | sed -n 's|.*[?&]sni=\([^&#]*\).*|\1|p')"
    TROJAN_OLD_PASS="$(urldecode "$TROJAN_OLD_PASS")"
}

trojan_deploy() {
    trojan_load_old
    local port pass sni ip cc uri

    bold "—— 部署 Trojan ——"
    echo
    # openssl 必须在 gen_hex 调用前就绪（默认值求值时会用到）
    ensure_cmd openssl openssl
    ask_port "监听 TCP 端口" "${TROJAN_OLD_PORT:-4443}" port
    ask_secret "连接密码" "${TROJAN_OLD_PASS:-$(gen_hex 16)}" pass
    ask_input "伪装域名 (SNI/证书 CN)" "${TROJAN_OLD_SNI:-www.cloudflare.com}" sni

    step "[1/5] 安装 Xray 核心…"
    xray_ensure || { echo; pause; return 1; }

    step "[2/5] 生成自签 TLS 证书 (CN=$sni)…"
    ensure_dir "$TROJAN_DIR"
    xray_selfcert "$TROJAN_DIR" "$sni" \
        || { err "证书生成失败"; echo; pause; return 1; }

    step "[3/5] 写入 Xray 配置…"
    cat > "$TROJAN_DIR/config.json" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": $port,
      "protocol": "trojan",
      "settings": {
        "clients": [ { "password": "$pass" } ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$TROJAN_DIR/server.crt",
              "keyFile": "$TROJAN_DIR/server.key"
            }
          ]
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls"] }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" } ]
}
EOF
    chmod 600 "$TROJAN_DIR/config.json"

    step "[4/5] 启动服务并设置开机自启…"
    if ! xray_deploy_service "$TROJAN_SVC" "$TROJAN_DIR/config.json"; then
        err "服务启动失败，请查看运行日志排查"
        echo; pause; return 1
    fi

    step "[5/5] 生成分享链接…"
    ip="$(get_pubip)"
    if [[ -z "$ip" ]]; then
        warn "未能自动获取公网 IP"
        ask_input "请手动输入公网 IP（v6 请带括号，如 [2a01::1]）" "" ip
        [[ -z "$ip" ]] && { err "未提供 IP，部署中止"; echo; pause; return 1; }
    fi
    cc="$(geo_cc)"; [[ -z "$cc" ]] && cc="VPS"
    uri="trojan://$(urlencode "$pass")@${ip}:${port}?sni=$(urlencode "$sni")&allowInsecure=1#${cc}_Trojan"
    printf '%s\n' "$uri" > "$TROJAN_LINK"
    chmod 600 "$TROJAN_LINK"

    fw_allow "$port" tcp 2>/dev/null || true

    echo
    ok "部署完成！服务运行中，开机自启已设置"
    warn "节点链接：$uri"
    dim  "使用自签证书，客户端需开启「跳过证书验证」"
    echo
    pause
}

trojan_link() {
    if [[ -f "$TROJAN_LINK" ]]; then cat "$TROJAN_LINK"; echo
    else warn "暂无节点链接，请先部署"; echo; fi
    pause
}

trojan_restart() {
    step "正在重启 Trojan…"
    if svc_restart "$TROJAN_SVC"; then ok "重启成功，服务运行正常"
    else err "重启失败，请查看运行日志"; fi
    echo; pause
}

trojan_logs() {
    info "最近 60 行日志（下方实时跟踪，Ctrl+C 停止）"
    echo
    svc_logs "$TROJAN_SVC" 60
    echo
    svc_logs_follow "$TROJAN_SVC"
}

trojan_uninstall() {
    confirm "确定彻底卸载 Trojan 吗？配置与证书将全部删除" || return 0
    step "停止并移除服务…"
    svc_uninstall "$TROJAN_SVC"
    step "删除配置…"
    rm -rf "$TROJAN_DIR"
    ok "Trojan 已彻底卸载"
    echo; pause
}

trojan_status() {
    bold "—— Trojan 状态 ——"
    echo
    if trojan_installed; then dim "已安装（Xray $(cat "$XRAY_VER_FILE" 2>/dev/null)）"
    else err "未安装"; echo; pause; return 0; fi
    if trojan_active; then ok "服务状态：运行中 (active)"
    else err "服务状态：未运行"; fi
    echo "开机自启：$(svc_enabled "$TROJAN_SVC" && echo 是 || echo 否)"
    echo "监听端口：$(trojan_port) (TCP)"
    echo
    pause
}
