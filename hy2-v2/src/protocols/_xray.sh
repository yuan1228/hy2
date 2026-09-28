#!/bin/bash
# ============================================================
# Yuan Panel · Xray 共享助手（内部使用，供 vless/trojan 模块引用）
# ============================================================

XRAY_BIN="$YUAN_BIN_DIR/xray"
XRAY_VER_FILE="$YUAN_BIN_DIR/xray.version"

xray_bin() { printf '%s' "$XRAY_BIN"; }

# 安装 / 更新 Xray 核心（GitHub 官方 release）
xray_ensure() {
    sysinfo
    local arch_dl ver url tmpdir
    case "$SYS_ARCH" in
        amd64) arch_dl="64" ;;
        arm64) arch_dl="arm64-v8a" ;;
        *) err "Xray 不支持该架构：$SYS_ARCH"; return 1 ;;
    esac

    ensure_cmd curl curl
    ensure_cmd unzip unzip

    step "获取 Xray 最新版本…"
    ver="$(curl -fsSL --max-time 20 https://api.github.com/repos/XTLS/Xray-core/releases/latest \
        | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    [[ -z "$ver" ]] && { err "无法获取 Xray 版本（网络或 GitHub API 异常）"; return 1; }

    if [[ -x "$XRAY_BIN" && "$(cat "$XRAY_VER_FILE" 2>/dev/null)" == "$ver" ]]; then
        dim "Xray 已是最新 ($ver)，跳过下载"
        return 0
    fi

    step "下载 Xray $ver ($arch_dl)…"
    url="https://github.com/XTLS/Xray-core/releases/download/${ver}/Xray-linux-${arch_dl}.zip"
    tmpdir="$(mktemp -d)"
    if ! curl -fsSL --max-time 120 --retry 2 "$url" -o "$tmpdir/xray.zip"; then
        rm -rf "$tmpdir"; err "Xray 下载失败"; return 1
    fi
    mkdir -p "$YUAN_BIN_DIR"
    unzip -o -q "$tmpdir/xray.zip" xray -d "$YUAN_BIN_DIR"
    rm -rf "$tmpdir"
    chmod +x "$XRAY_BIN"
    printf '%s' "$ver" > "$XRAY_VER_FILE"
    ok "Xray $ver 安装完成"
}

# 生成 REALITY 密钥对，输出 "私钥|公钥"
# 注意：xray 26.x 输出含 PrivateKey:/Password (PublicKey):/Hash32: 三行，按关键字解析
xray_keypair() {
    local out priv pub
    out="$("$XRAY_BIN" x25519 2>/dev/null)" || return 1
    priv="$(printf '%s' "$out" | grep -i 'private' | grep -oE '[^: ]+$' | head -1)"
    pub="$(printf '%s' "$out" | grep -i 'public'  | grep -oE '[^: ]+$' | head -1)"
    [[ -n "$priv" && -n "$pub" ]] || return 1
    printf '%s|%s' "$priv" "$pub"
}

xray_uuid() {
    "$XRAY_BIN" uuid 2>/dev/null | tr -d '[:space:]'
}

xray_shortid() {
    openssl rand -hex 8 2>/dev/null | cut -c1-8
}

# 生成自签证书（Trojan TLS 用），参数：目录 CN
xray_selfcert() {
    local dir="$1" cn="$2"
    ensure_cmd openssl openssl
    mkdir -p "$dir"
    openssl ecparam -genkey -name prime256v1 -out "$dir/server.key" 2>/dev/null
    openssl req -new -x509 -days 36500 -key "$dir/server.key" \
        -out "$dir/server.crt" -subj "/CN=$cn" 2>/dev/null
    chmod 600 "$dir/server.key"
    chmod 644 "$dir/server.crt"
    [[ -s "$dir/server.key" && -s "$dir/server.crt" ]]
}

# 写入 xray systemd 单元并启动，参数：服务名 配置路径
xray_deploy_service() {
    local svc="$1" conf="$2"
    "$XRAY_BIN" -test -config "$conf" >/dev/null 2>&1 \
        || { err "Xray 配置校验未通过"; return 1; }
    cat > "/etc/systemd/system/${svc}.service" <<EOF
[Unit]
Description=Yuan Panel Xray ($svc)
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=$XRAY_BIN run -config $conf
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    svc_restart "$svc"
}
