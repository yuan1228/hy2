#!/bin/bash
# ============================================================
# Yuan VPS 工具箱 · 协议模块：Shadowsocks (2022)
# shadowsocks-rust，轻量快速，适合做备用/兜底协议
# ============================================================

SS_ID="ss"
SS_NAME="Shadowsocks"
SS_DESC="2022 协议，轻量快速，兼容性最广"
SS_DIR="$YUAN_CONF/ss"
SS_SVC="yuan-ss.service"
SS_LINK="$SS_DIR/link.txt"
SS_BIN="$YUAN_BIN_DIR/ssserver"
SS_VER_FILE="$YUAN_BIN_DIR/ssserver.version"
SS_METHOD="2022-blake3-aes-128-gcm"

ss_installed() { [[ -f "$SS_DIR/config.json" && -x "$SS_BIN" ]]; }
ss_active()    { svc_active "$SS_SVC"; }
ss_port() {
    grep -oE '"server_port":[[:space:]]*[0-9]+' "$SS_DIR/config.json" 2>/dev/null \
        | grep -oE '[0-9]+' | head -1
}

# 安装 shadowsocks-rust 的 ssserver
ss_ensure_bin() {
    sysinfo
    local arch_dl ver url tmpdir
    # Alpine 用 musl，glibc 构建在其上无法运行，必须选 -musl 包
    local libc_suffix=""
    [[ "$SYS_OS" == "alpine" ]] && libc_suffix="-musl"
    case "$SYS_ARCH" in
        amd64) arch_dl="x86_64-unknown-linux-gnu${libc_suffix}" ;;
        arm64) arch_dl="aarch64-unknown-linux-gnu${libc_suffix}" ;;
        *) err "Shadowsocks 不支持该架构：$SYS_ARCH"; return 1 ;;
    esac

    ensure_cmd curl curl
    ensure_cmd tar tar

    step "获取 shadowsocks-rust 最新版本…"
    ver="$(github_latest_tag "shadowsocks/shadowsocks-rust")" \
        || { err "无法获取版本（网络或 GitHub API 异常）"; return 1; }

    if [[ -x "$SS_BIN" && "$(cat "$SS_VER_FILE" 2>/dev/null)" == "$ver" ]]; then
        if "$SS_BIN" --version >/dev/null 2>&1; then
            dim "ssserver 已是最新 ($ver)，跳过下载"
            return 0
        fi
        warn "已存在的 ssserver 二进制已损坏，重新下载…"
    fi

    step "下载 ssserver $ver…"
    url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${ver}/shadowsocks-${ver#v}.${arch_dl}.tar.xz"
    tmpdir="$(mktemp -d)"
    if ! curl -fsSL --max-time 120 --retry 2 "$url" -o "$tmpdir/ss.tar.xz"; then
        rm -rf "$tmpdir"
        # GitHub 无 IPv6，纯 v6 机器下载失败时改走 apt（Debian 官方源有 IPv6）
        if command -v apt-get >/dev/null 2>&1; then
            warn "GitHub 下载失败，改用 apt 安装 shadowsocks-rust…"
            if apt-get update -qq 2>/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq shadowsocks-rust 2>/dev/null; then
                apt_bin="$(command -v ssserver)"
                if [[ -x "$apt_bin" ]]; then
                    mkdir -p "$YUAN_BIN_DIR"
                    cp -f "$apt_bin" "$SS_BIN" && chmod +x "$SS_BIN"
                    ver="apt-$(dpkg-query -W -f='${Version}' shadowsocks-rust 2>/dev/null | cut -d'-' -f1)"
                    printf '%s' "$ver" > "$SS_VER_FILE"
                    ok "ssserver 已通过 apt 安装 ($ver)"
                    return 0
                fi
            fi
        fi
        err "ssserver 下载失败"; return 1
    fi
    mkdir -p "$YUAN_BIN_DIR"
    tar -xJf "$tmpdir/ss.tar.xz" -C "$tmpdir"
    # 包内二进制名为 ssserver
    [[ -f "$tmpdir/ssserver" ]] || { rm -rf "$tmpdir"; err "解压后未找到 ssserver"; return 1; }
    mv "$tmpdir/ssserver" "$SS_BIN"
    rm -rf "$tmpdir"
    chmod +x "$SS_BIN"
    printf '%s' "$ver" > "$SS_VER_FILE"
    ok "ssserver $ver 安装完成"
}

ss_load_old() {
    SS_OLD_PORT=""; SS_OLD_PASS=""
    local link=""
    [[ -f "$SS_LINK" ]] && link="$(cat "$SS_LINK")"
    [[ -z "$link" ]] && return 0
    SS_OLD_PORT="$(printf '%s' "$link" | sed -n 's|^ss://[^@]*@[^:]*:\([0-9]\{1,5\}\)#.*|\1|p')"
    # 密码从 base64 的 userinfo 中解析
    local ui
    ui="$(printf '%s' "$link" | sed -n 's|^ss://\([^@]*\)@.*|\1|p' | tr '_-' '/+' )"
    SS_OLD_PASS="$(printf '%s' "$ui" | base64 -d 2>/dev/null | cut -d: -f2-)"
}

ss_deploy() {
    ss_load_old
    local port pass ip cc userinfo uri

    bold "—— 部署 Shadowsocks (2022) ——"
    echo
    # openssl 必须在 gen_pass 调用前就绪（默认值求值时会用到）
    ensure_cmd openssl openssl
    ask_port "监听端口 (TCP+UDP)" "${SS_OLD_PORT:-8388}" port
    ask_secret "连接密码" "${SS_OLD_PASS:-$(gen_pass 24)}" pass
    dim "加密方式：$SS_METHOD（固定，安全性与性能兼顾）"
    echo

    step "[1/4] 安装 ssserver…"
    ss_ensure_bin || { echo; pause; return 1; }

    step "[2/4] 写入配置…"
    ensure_dir "$SS_DIR"
    cat > "$SS_DIR/config.json" <<EOF
{
    "server": "::",
    "server_port": $port,
    "password": "$pass",
    "method": "$SS_METHOD",
    "mode": "tcp_and_udp",
    "timeout": 300,
    "fast_open": true
}
EOF
    chmod 600 "$SS_DIR/config.json"

    step "[3/4] 安装服务并设置开机自启…"
    svc_install "$SS_SVC" "Yuan VPS 工具箱 Shadowsocks" \
        "$SS_BIN" "-c $SS_DIR/config.json" \
        || { err "服务安装失败"; echo; pause; return 1; }
    if ! svc_restart "$SS_SVC"; then
        err "服务启动失败，请查看运行日志排查"
        echo; pause; return 1
    fi

    step "[4/4] 生成分享链接…"
    ip="$(get_pubip)"
    if [[ -z "$ip" ]]; then
        warn "未能自动获取公网 IP"
        ask_input "请手动输入公网 IP（v6 请带括号，如 [2a01::1]）" "" ip
        [[ -z "$ip" ]] && { err "未提供 IP，部署中止"; echo; pause; return 1; }
    fi
    cc="$(geo_cc)"; [[ -z "$cc" ]] && cc="VPS"
    echo "  检测到国码：$cc"
    read -rp "  国码是否正确？直接回车确认，或输入正确国码（如 DE/US/JP）: " cc_input < /dev/tty
    [[ -n "$cc_input" ]] && cc="$(echo "$cc_input" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')"
    userinfo="$(b64url "$SS_METHOD:$pass")"
    uri="ss://${userinfo}@${ip}:${port}#${cc}_SS"
    printf '%s\n' "$uri" > "$SS_LINK"
    chmod 600 "$SS_LINK"

    fw_allow "$port" tcp 2>/dev/null || true
    fw_allow "$port" udp 2>/dev/null || true

    echo
    ok "部署完成！服务运行中，开机自启已设置"
    warn "节点链接：$uri"
    echo
    pause
}

ss_link() {
    if [[ -f "$SS_LINK" ]]; then cat "$SS_LINK"; echo
    else warn "暂无节点链接，请先部署"; echo; fi
    pause
}

ss_restart() {
    step "正在重启 Shadowsocks…"
    if svc_restart "$SS_SVC"; then ok "重启成功，服务运行正常"
    else err "重启失败，请查看运行日志"; fi
    echo; pause
}

ss_logs() {
    info "最近 60 行日志（下方实时跟踪，Ctrl+C 停止）"
    echo
    svc_logs "$SS_SVC" 60
    echo
    svc_logs_follow "$SS_SVC"
}

ss_uninstall() {
    confirm "确定彻底卸载 Shadowsocks 吗？配置将全部删除" || return 0
    step "停止并移除服务…"
    svc_uninstall "$SS_SVC"
    step "删除配置…"
    rm -rf "$SS_DIR"
    ok "Shadowsocks 已彻底卸载"
    echo; pause
}

ss_status() {
    bold "—— Shadowsocks 状态 ——"
    echo
    if ss_installed; then dim "已安装（ssserver $(cat "$SS_VER_FILE" 2>/dev/null)）"
    else err "未安装"; echo; pause; return 0; fi
    if ss_active; then ok "服务状态：运行中 (active)"
    else err "服务状态：未运行"; fi
    echo "开机自启：$(svc_enabled "$SS_SVC" && echo 是 || echo 否)"
    echo "监听端口：$(ss_port) (TCP+UDP)"
    echo "加密方式：$SS_METHOD"
    echo
    pause
}
