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
HY2_HOP_CONF="$HY2_DIR/hop.conf"
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
    HY2_OLD_PORT=""; HY2_OLD_PASS=""; HY2_OLD_SNI=""; HY2_OLD_OBFS=""; HY2_OLD_MPORT=""
    local link=""
    [[ -f "$HY2_LINK" ]] && link="$(cat "$HY2_LINK")"
    [[ -z "$link" && -f "$HY2_LEGACY_LINK" ]] && link="$(cat "$HY2_LEGACY_LINK")"
    [[ -z "$link" ]] && return 0
    HY2_OLD_PASS="$(printf '%s' "$link" | sed -n 's|^hysteria2://\([^@]*\)@.*|\1|p')"
    HY2_OLD_PORT="$(printf '%s' "$link" | sed -n 's|^hysteria2://[^@]*@[^:]*:\([0-9]\{1,5\}\)/?.*|\1|p')"
    HY2_OLD_SNI="$(printf '%s' "$link" | sed -n 's|.*[?&]sni=\([^&#]*\).*|\1|p')"
    HY2_OLD_OBFS="$(printf '%s' "$link" | sed -n 's|.*[?&]obfs-password=\([^&#]*\).*|\1|p')"
    HY2_OLD_MPORT="$(printf '%s' "$link" | sed -n 's|.*[?&]mport=\([^&#]*\).*|\1|p')"
    HY2_OLD_PASS="$(urldecode "$HY2_OLD_PASS")"
    HY2_OLD_OBFS="$(urldecode "$HY2_OLD_OBFS")"
}

# 安装 hysteria 二进制
# systemd 系统：走官方安装脚本；Alpine/OpenRC：官方脚本强制要求 systemd，
# 改为从 GitHub releases 直接下载二进制（行为等价，且避开官方脚本的 grep -P 等兼容问题）
hy2_ensure_bin() {
    detect_init
    # 光存在不够：必须能执行（上次下载中断的半截文件也要重下）
    if [[ -x "$HY2_BIN" ]]; then
        if "$HY2_BIN" version >/dev/null 2>&1; then
            dim "hysteria 已安装，跳过下载"
            return 0
        fi
        warn "已存在的 hysteria 二进制已损坏，重新下载…"
        rm -f "$HY2_BIN"
    fi
    ensure_cmd curl curl
    if [[ "$SYS_INIT" == "systemd" ]]; then
        # 先试官方脚本（IPv4 下正常；纯 IPv6 下因 GitHub 无 v6 会失败）
        if bash <(curl -fsSL --max-time 60 https://get.hy2.sh/) 2>/dev/null; then
            : # 官方脚本成功
        else
            warn "官方安装脚本失败，尝试直接下载二进制…"
            # 直接从 GitHub 取（IPv4 可达时用）
            ver="$(github_latest_tag "apernet/hysteria" 2>/dev/null)"
            # github_latest_tag 返回的是 app/vX.Y.Z 格式？实际取 release tag
            # Hysteria 的 release tag 形如 app/v2.12.3，download 路径用 app/ 前缀
            dl_ok=0
            if [[ -n "$ver" ]]; then
                url="https://github.com/apernet/hysteria/releases/download/app/${ver}/hysteria-linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
                if curl -fsSL --max-time 120 --retry 2 "$url" -o "$HY2_BIN" 2>/dev/null; then
                    chmod +x "$HY2_BIN"
                    dl_ok=1
                fi
            fi
            # 纯 IPv6 兜底：临时 DNS64/NAT64 拉 GitHub 官方二进制，完事恢复，不留残留
            if [[ "$dl_ok" != "1" ]]; then
                case "$(uname -m)" in
                    x86_64) _n64_arch="amd64" ;;
                    aarch64) _n64_arch="arm64" ;;
                    *) _n64_arch="" ;;
                esac
                if [[ -n "$_n64_arch" ]]; then
                    _n64_ver="${HY2_VER:-v2.12.3}"
                    _n64_url="https://github.com/apernet/hysteria/releases/download/${_n64_ver}/hysteria-linux-${_n64_arch}"
                    dim "纯 IPv6，临时经 NAT64 下载 hysteria…"
                    if nat64_fetch "$_n64_url" "$HY2_BIN" 2>/dev/null; then
                        chmod +x "$HY2_BIN"
                        if "$HY2_BIN" version >/dev/null 2>&1; then
                            dl_ok=1
                            dim "已通过临时 NAT64 获取 hysteria 二进制"
                        fi
                    fi
                fi
            fi
            if [[ "$dl_ok" != "1" ]]; then
                err "Hysteria2 二进制下载失败"
                echo
                # 纯 IPv6 检测：GitHub 无 IPv6，这是根本原因
                if ! curl -6s --max-time 5 -o /dev/null https://github.com 2>/dev/null; then
                    warn "检测到纯 IPv6 网络：GitHub（含 api.github.com）没有 IPv6 地址，"
                    warn "Hysteria 官方只在 GitHub releases 发布二进制，无法自动下载。"
                    echo
                    info "手动安装步骤（在有 IPv4 的电脑/手机上操作一次即可）："
                    info "  1. 下载：https://github.com/apernet/hysteria/releases/latest"
                    info "     选 hysteria-linux-amd64（x86_64）或 hysteria-linux-arm64"
                    info "  2. 传到本机 /usr/local/bin/hysteria（scp/sftp/面板文件管理均可）"
                    info "  3. 执行：chmod +x /usr/local/bin/hysteria"
                    info "  4. 重新运行 yuan → Hysteria2 → 安装，会跳过下载直接部署"
                else
                    err "请检查网络后重试"
                fi
                echo; pause; return 1
            fi
        fi
    else
        local arch url
        case "$(uname -m)" in
            x86_64)  arch="amd64" ;;
            aarch64) arch="arm64" ;;
            *) err "Hysteria2 不支持该架构：$(uname -m)"; return 1 ;;
        esac
        step "下载 hysteria 二进制…"
        url="https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-${arch}"
        if ! curl -fsSL --max-time 120 --retry 2 "$url" -o "$HY2_BIN"; then
            # GitHub 无 IPv6，纯 v6 下改试 apk（Alpine 官方源有 IPv6）
            if command -v apk >/dev/null 2>&1; then
                warn "GitHub 下载失败，改用 apk 安装 hysteria…"
                if apk add --no-cache hysteria 2>/dev/null; then
                    apk_bin="$(command -v hysteria)"
                    if [[ -x "$apk_bin" && "$apk_bin" != "$HY2_BIN" ]]; then
                        cp -f "$apk_bin" "$HY2_BIN"
                    fi
                    chmod +x "$HY2_BIN" 2>/dev/null || true
                    if [[ -x "$HY2_BIN" ]]; then
                        ok "hysteria 已通过 apk 安装"
                    else
                        err "hysteria 下载失败，请检查网络后重试"
                        return 1
                    fi
                else
                    err "hysteria 下载失败，请检查网络后重试"
                    return 1
                fi
            else
                err "hysteria 下载失败，请检查网络后重试"
                return 1
            fi
        else
            chmod +x "$HY2_BIN"
        fi
    fi
    if [[ ! -x "$HY2_BIN" ]] || ! "$HY2_BIN" version >/dev/null 2>&1; then
        err "hysteria 二进制校验失败（文件损坏或架构不匹配）"
        return 1
    fi
    ok "hysteria 安装完成"
}

# ============================================================
# 端口跳跃（Port Hopping）
# 原理：iptables/nftables 把一段 UDP 端口 DNAT 到主端口，
# 客户端用 mport 参数定时换端口连接，GFW 难以按端口封锁。
# 链接使用合规的 mport 查询参数，不用逗号写法（标准 URL 库不认逗号端口）。
# ============================================================

# 设置端口跳跃：hy2_setup_hop <主端口> <起始端口> <结束端口>
hy2_setup_hop() {
    local main_port="$1" start="$2" end="$3" be
    be="$(fw_backend)"

    # 无可用后端时尝试自动安装 iptables
    if [[ "$be" == "none" ]]; then
        if command -v apk >/dev/null 2>&1; then
            step "安装 iptables…"
            apk add --no-cache iptables >/dev/null 2>&1 \
                || { err "iptables 安装失败"; return 1; }
            be="iptables"
        elif command -v apt-get >/dev/null 2>&1; then
            step "安装 iptables…"
            apt-get update -qq >/dev/null 2>&1
            apt-get install -y -qq iptables >/dev/null 2>&1 \
                || { err "iptables 安装失败"; return 1; }
            be="iptables"
        else
            err "未检测到 nftables/iptables，且无法自动安装"
            return 1
        fi
    fi

    case "$be" in
        iptables)
            # 幂等：先删旧规则再加（IPv4）
            iptables -t nat -D PREROUTING -p udp --dport "${start}:${end}" \
                -j DNAT --to-destination ":${main_port}" 2>/dev/null
            iptables -t nat -A PREROUTING -p udp --dport "${start}:${end}" \
                -j DNAT --to-destination ":${main_port}" \
                || { err "iptables DNAT 规则添加失败"; return 1; }
            # IPv6：同网段加 ip6tables 规则（纯 v6 机器必需）
            if command -v ip6tables >/dev/null 2>&1; then
                ip6tables -t nat -D PREROUTING -p udp --dport "${start}:${end}" \
                    -j DNAT --to-destination ":${main_port}" 2>/dev/null
                ip6tables -t nat -A PREROUTING -p udp --dport "${start}:${end}" \
                    -j DNAT --to-destination ":${main_port}" 2>/dev/null || true
            fi
            fw_ipt_save
            # Alpine：iptables 服务开机从 /etc/iptables/rules-save 恢复
            if command -v rc-update >/dev/null 2>&1; then
                mkdir -p /etc/iptables
                iptables-save > /etc/iptables/rules-save 2>/dev/null
                rc-update add iptables default >/dev/null 2>&1
            fi
            ;;
        nft)
            nft list table ip yuan_nat >/dev/null 2>&1 || nft add table ip yuan_nat
            nft list chain ip yuan_nat prerouting >/dev/null 2>&1 || \
                nft add chain ip yuan_nat prerouting \
                    '{ type nat hook prerouting priority -100; }' 2>/dev/null
            # IPv6：加 ip6 表（纯 v6 机器必需）
            nft list table ip6 yuan_nat6 >/dev/null 2>&1 || nft add table ip6 yuan_nat6
            nft list chain ip6 yuan_nat6 prerouting >/dev/null 2>&1 || \
                nft add chain ip6 yuan_nat6 prerouting \
                    '{ type nat hook prerouting priority -100; }' 2>/dev/null
            # 幂等：删旧加新
            local handle
            handle="$(nft -a list chain ip yuan_nat prerouting 2>/dev/null \
                | grep -oE "udp dport ${start}-${end}.*handle [0-9]+" \
                | grep -oE 'handle [0-9]+' | awk '{print $2}')"
            [[ -n "$handle" ]] && \
                nft delete rule ip yuan_nat prerouting handle "$handle" 2>/dev/null
            nft add rule ip yuan_nat prerouting udp dport "${start}-${end}" \
                dnat to ":${main_port}" \
                || { err "nftables DNAT 规则添加失败"; return 1; }
            # IPv6 规则
            local handle6
            handle6="$(nft -a list chain ip6 yuan_nat6 prerouting 2>/dev/null \
                | grep -oE "udp dport ${start}-${end}.*handle [0-9]+" \
                | grep -oE 'handle [0-9]+' | awk '{print $2}')"
            [[ -n "$handle6" ]] && \
                nft delete rule ip6 yuan_nat6 prerouting handle "$handle6" 2>/dev/null
            nft add rule ip6 yuan_nat6 prerouting udp dport "${start}-${end}" \
                dnat to ":${main_port}" 2>/dev/null || true
            mkdir -p /etc/nftables.d
            nft list table ip yuan_nat > /etc/nftables.d/yuan_nat.nft 2>/dev/null
            nft list table ip6 yuan_nat6 > /etc/nftables.d/yuan_nat6.nft 2>/dev/null
            ;;
    esac

    # 落盘配置，供卸载/状态查询/覆盖安装识别
    cat > "$HY2_HOP_CONF" <<EOF
HOP_MAIN_PORT=$main_port
HOP_START=$start
HOP_END=$end
HOP_BACKEND=$be
EOF
    chmod 600 "$HY2_HOP_CONF"
    ok "端口跳跃已启用：UDP ${start}-${end} → ${main_port}（mport 参数）"
}

# 移除端口跳跃（卸载/重装时调用）
hy2_remove_hop() {
    [[ -f "$HY2_HOP_CONF" ]] || return 0
    # shellcheck disable=SC1090
    source "$HY2_HOP_CONF"
    case "$HOP_BACKEND" in
        iptables)
            iptables -t nat -D PREROUTING -p udp \
                --dport "${HOP_START}:${HOP_END}" \
                -j DNAT --to-destination ":${HOP_MAIN_PORT}" 2>/dev/null
            # IPv6 规则清理
            if command -v ip6tables >/dev/null 2>&1; then
                ip6tables -t nat -D PREROUTING -p udp \
                    --dport "${HOP_START}:${HOP_END}" \
                    -j DNAT --to-destination ":${HOP_MAIN_PORT}" 2>/dev/null
            fi
            fw_ipt_save
            if command -v rc-update >/dev/null 2>&1; then
                iptables-save > /etc/iptables/rules-save 2>/dev/null
            fi
            ;;
        nft)
            local handle
            handle="$(nft -a list chain ip yuan_nat prerouting 2>/dev/null \
                | grep -oE "udp dport ${HOP_START}-${HOP_END}.*handle [0-9]+" \
                | grep -oE 'handle [0-9]+' | awk '{print $2}')"
            [[ -n "$handle" ]] && \
                nft delete rule ip yuan_nat prerouting handle "$handle" 2>/dev/null
            # IPv6 规则清理
            local handle6
            handle6="$(nft -a list chain ip6 yuan_nat6 prerouting 2>/dev/null \
                | grep -oE "udp dport ${HOP_START}-${HOP_END}.*handle [0-9]+" \
                | grep -oE 'handle [0-9]+' | awk '{print $2}')"
            [[ -n "$handle6" ]] && \
                nft delete rule ip6 yuan_nat6 prerouting handle "$handle6" 2>/dev/null
            mkdir -p /etc/nftables.d
            nft list table ip yuan_nat > /etc/nftables.d/yuan_nat.nft 2>/dev/null
            nft list table ip6 yuan_nat6 > /etc/nftables.d/yuan_nat6.nft 2>/dev/null
            nft list table ip6 yuan_nat6 > /etc/nftables.d/yuan_nat6.nft 2>/dev/null
            ;;
    esac
    rm -f "$HY2_HOP_CONF"
    ok "端口跳跃规则已移除"
}

# 是否启用了端口跳跃
hy2_hop_enabled() { [[ -f "$HY2_HOP_CONF" ]]; }
hy2_hop_range() {
    [[ -f "$HY2_HOP_CONF" ]] || return 1
    # shellcheck disable=SC1090
    source "$HY2_HOP_CONF"
    echo "${HOP_START}-${HOP_END}"
}

hy2_deploy() {
    hy2_load_old
    local port pass sni obfs ip cc uri hop_enable="" hop_range="" hop_start="" hop_end=""

    bold "—— 部署 Hysteria2 ——"
    echo
    # openssl 必须在 gen_hex/gen_pass 调用前就绪（默认值求值时会用到）
    ensure_cmd openssl openssl
    ask_port "监听 UDP 端口" "${HY2_OLD_PORT:-$((40000 + RANDOM % 10000))}" port
    ask_secret "认证密码" "${HY2_OLD_PASS:-$(gen_hex 16)}" pass
    ask_input "伪装域名 (SNI)" "${HY2_OLD_SNI:-www.cloudflare.com}" sni
    [[ -z "${HY2_OLD_OBFS:-}" ]] && HY2_OLD_OBFS="$(gen_hex 8)"
    obfs="$HY2_OLD_OBFS"

    # 端口跳跃（可选）：覆盖安装时沿用旧配置
    if [[ "${QUICK:-0}" != "1" ]]; then
        echo
        dim "端口跳跃：把一段 UDP 端口转发到主端口，客户端定时换端口连接，"
        dim "可有效对抗 GFW 按端口封锁（间歇性阻断）。链接使用标准 mport 参数。"
        local hop_def="n"
        [[ -n "${HY2_OLD_MPORT:-}" ]] && hop_def="y"
        if [[ "$hop_def" == "y" ]]; then
            warn "检测到旧节点启用了端口跳跃（${HY2_OLD_MPORT}）"
        fi
        if confirm "启用端口跳跃？"; then
            hop_enable=1
            ask_input "跳跃端口范围（格式 起始-结束）" "${HY2_OLD_MPORT:-20000-30000}" hop_range
            if [[ ! "$hop_range" =~ ^[0-9]+-[0-9]+$ ]]; then
                err "范围格式不合法，应为 起始-结束（如 20000-30000）"
                echo; pause; return 1
            fi
            hop_start="${hop_range%-*}"; hop_end="${hop_range#*-}"
            if ! valid_port "$hop_start" || ! valid_port "$hop_end" || (( hop_start >= hop_end )); then
                err "端口范围不合法：$hop_range"
                echo; pause; return 1
            fi
            if (( hop_start <= port && port <= hop_end )); then
                err "跳跃范围不能包含主端口 $port，请换个范围"
                echo; pause; return 1
            fi
        fi
    fi

    step "[1/6] 安装 Hysteria2 官方核心…"
    hy2_ensure_bin || { echo; pause; return 1; }

    step "[2/6] 准备配置目录…"
    ensure_dir "$HY2_DIR"

    step "[3/6] 生成自签 TLS 证书 (CN=$sni)…"
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

    step "[5/6] 安装服务并设置开机自启…"
    svc_install "$HY2_SVC" "Yuan VPS 工具箱 Hysteria2" \
        "$HY2_BIN" "server --config $HY2_DIR/config.yaml" \
        || { err "服务安装失败"; echo; pause; return 1; }
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
    uri="hysteria2://$(urlencode "$pass")@${ip}:${port}/?insecure=1&sni=$(urlencode "$sni")&obfs=salamander&obfs-password=$(urlencode "$obfs")"

    # 端口跳跃：先建转发规则，再拼 mport 参数
    if [[ -n "$hop_enable" ]]; then
        # 重装时先清旧规则，避免残留
        hy2_remove_hop 2>/dev/null
        step "[7/7] 设置端口跳跃转发（UDP ${hop_start}-${hop_end} → ${port}）…"
        if ! hy2_setup_hop "$port" "$hop_start" "$hop_end"; then
            err "端口跳跃设置失败，部署中止（主节点未受影响，可重装重试）"
            echo; pause; return 1
        fi
        uri="${uri}&mport=${hop_start}-${hop_end}"
    else
        # 未启用跳跃时，清理可能残留的旧规则
        hy2_remove_hop 2>/dev/null
    fi
    uri="${uri}#${cc}_HY2"
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
    svc_logs "$HY2_SVC" 60
    echo
    svc_logs_follow "$HY2_SVC"
}

hy2_uninstall() {
    confirm "确定彻底卸载 Hysteria2 吗？配置与证书将全部删除" || return 0
    step "移除端口跳跃规则…"
    hy2_remove_hop 2>/dev/null
    step "停止并移除服务…"
    svc_uninstall "$HY2_SVC"
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
    if hy2_hop_enabled; then
        echo -e "端口跳跃：${C_GRN}已启用${C_RST}（UDP $(hy2_hop_range) → $(hy2_port)）"
    else
        echo "端口跳跃：未启用"
    fi
    echo "核心版本：$("$HY2_BIN" version 2>/dev/null | head -1)"
    echo
    pause
}
