#!/bin/bash
# ============================================================
# Yuan Panel · 协议模块：VLESS + REALITY（Xray）
# TLS 指纹伪装，无需域名与证书，抗封锁能力强
# 注意：REALITY 伪装目标证书须 < 8192 字节，避开大证书站点
# ============================================================
# shellcheck disable=SC1091
source "$YUAN_ROOT/src/protocols/_xray.sh"

VLESS_ID="vless"
VLESS_NAME="VLESS + REALITY"
VLESS_DESC="Xray，TLS 指纹伪装，无需域名"
VLESS_DIR="$YUAN_CONF/vless"
VLESS_SVC="yuan-vless.service"
VLESS_LINK="$VLESS_DIR/link.txt"
# 安全的 REALITY 伪装目标（小证书站点）
VLESS_SAFE_DESTS=("www.cloudflare.com" "www.apple.com" "www.amazon.com")

vless_installed() { [[ -f "$VLESS_DIR/config.json" && -x "$XRAY_BIN" ]]; }
vless_active()    { svc_active "$VLESS_SVC"; }
vless_port() {
    grep -oE '"port":[[:space:]]*[0-9]+' "$VLESS_DIR/config.json" 2>/dev/null \
        | grep -oE '[0-9]+' | head -1
}

vless_load_old() {
    VLESS_OLD_PORT=""; VLESS_OLD_SNI=""
    local link=""
    [[ -f "$VLESS_LINK" ]] && link="$(cat "$VLESS_LINK")"
    [[ -z "$link" ]] && return 0
    VLESS_OLD_PORT="$(printf '%s' "$link" | sed -n 's|^vless://[^@]*@[^:]*:\([0-9]\{1,5\}\)?.*|\1|p')"
    VLESS_OLD_SNI="$(printf '%s' "$link" | sed -n 's|.*[?&]sni=\([^&#]*\).*|\1|p')"
}

vless_deploy() {
    vless_load_old
    local port sni uuid kp priv pub sid ip cc uri dest i

    bold "—— 部署 VLESS + REALITY ——"
    echo
    ask_port "监听 TCP 端口" "${VLESS_OLD_PORT:-443}" port

    echo "可选的伪装目标（SNI）："
    for i in "${!VLESS_SAFE_DESTS[@]}"; do
        echo "  $((i+1)). ${VLESS_SAFE_DESTS[$i]}"
    done
    ask_input "选择或直接输入域名" "${VLESS_OLD_SNI:-${VLESS_SAFE_DESTS[0]}}" sni
    if [[ "$sni" =~ ^[1-3]$ ]]; then
        sni="${VLESS_SAFE_DESTS[$((sni-1))]}"
    fi
    dest="${sni}:443"

    step "[1/5] 安装 Xray 核心…"
    xray_ensure || { echo; pause; return 1; }

    step "[2/5] 生成 UUID 与 REALITY 密钥对…"
    uuid="$(xray_uuid)"; [[ -n "$uuid" ]] || { err "UUID 生成失败"; echo; pause; return 1; }
    kp="$(xray_keypair)"; [[ -n "$kp" ]] || { err "密钥对生成失败"; echo; pause; return 1; }
    priv="${kp%%|*}"; pub="${kp##*|}"
    sid="$(xray_shortid)"

    step "[3/5] 写入 Xray 配置…"
    ensure_dir "$VLESS_DIR"
    cat > "$VLESS_DIR/config.json" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": $port,
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "$uuid", "flow": "xtls-rprx-vision" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$dest",
          "xver": 0,
          "serverNames": [ "$sni" ],
          "privateKey": "$priv",
          "shortIds": [ "$sid" ]
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" } ]
}
EOF
    chmod 600 "$VLESS_DIR/config.json"

    step "[4/5] 启动服务并设置开机自启…"
    if ! xray_deploy_service "$VLESS_SVC" "$VLESS_DIR/config.json"; then
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
    uri="vless://${uuid}@${ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$(urlencode "$sni")&fp=chrome&pbk=$(urlencode "$pub")&sid=${sid}&type=tcp#${cc}_VLESS"
    printf '%s\n' "$uri" > "$VLESS_LINK"
    chmod 600 "$VLESS_LINK"

    fw_allow "$port" tcp 2>/dev/null || true

    echo
    ok "部署完成！服务运行中，开机自启已设置"
    warn "节点链接：$uri"
    dim  "公钥/UUID 已写入配置，链接已保存至 $VLESS_LINK（权限 600）"
    echo
    pause
}

vless_link() {
    if [[ -f "$VLESS_LINK" ]]; then cat "$VLESS_LINK"; echo
    else warn "暂无节点链接，请先部署"; echo; fi
    pause
}

vless_restart() {
    step "正在重启 VLESS…"
    if svc_restart "$VLESS_SVC"; then ok "重启成功，服务运行正常"
    else err "重启失败，请查看运行日志"; fi
    echo; pause
}

vless_logs() {
    info "最近 60 行日志（下方实时跟踪，Ctrl+C 停止）"
    echo
    journalctl -u "$VLESS_SVC" -n 60 --no-pager
    echo
    journalctl -u "$VLESS_SVC" -f --output cat
}

vless_uninstall() {
    confirm "确定彻底卸载 VLESS + REALITY 吗？配置与密钥将全部删除" || return 0
    systemctl stop "$VLESS_SVC" 2>/dev/null
    systemctl disable "$VLESS_SVC" 2>/dev/null
    rm -f "/etc/systemd/system/${VLESS_SVC}.service"
    systemctl daemon-reload 2>/dev/null
    rm -rf "$VLESS_DIR"
    ok "VLESS + REALITY 已彻底卸载"
    echo; pause
}

vless_status() {
    bold "—— VLESS + REALITY 状态 ——"
    echo
    if vless_installed; then dim "已安装（Xray $(cat "$XRAY_VER_FILE" 2>/dev/null)）"
    else err "未安装"; echo; pause; return 0; fi
    if vless_active; then ok "服务状态：运行中 (active)"
    else err "服务状态：未运行"; fi
    echo "开机自启：$(svc_enabled "$VLESS_SVC" && echo 是 || echo 否)"
    echo "监听端口：$(vless_port) (TCP)"
    echo
    pause
}
