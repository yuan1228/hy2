#!/bin/bash
# ============================================================
# Yuan VPS 工具箱 · 系统模块：防火墙管理
# 自动识别 nftables / iptables，仅放行必要端口
# 设计原则：默认放行 SSH(22) + 已部署协议端口，其余入站拒绝
# ============================================================

# 检测可用后端：nft / iptables / none
fw_backend() {
    if command -v nft >/dev/null 2>&1; then echo nft
    elif command -v iptables >/dev/null 2>&1; then echo iptables
    else echo none; fi
}

# 放行端口：fw_allow <port> <tcp|udp|both>
fw_allow() {
    local port="$1" proto="${2:-both}" be
    valid_port "$port" || return 1
    be="$(fw_backend)"
    case "$be" in
        nft)
            nft list table inet yuan >/dev/null 2>&1 || fw_nft_init
            for p in $(fw_proto_list "$proto"); do
                nft add rule inet yuan input "$p" dport "$port" accept 2>/dev/null
            done
            fw_nft_save
            ;;
        iptables)
            for p in $(fw_proto_list "$proto"); do
                iptables -C INPUT -p "$p" --dport "$port" -j ACCEPT 2>/dev/null \
                    || iptables -I INPUT -p "$p" --dport "$port" -j ACCEPT
            done
            fw_ipt_save
            ;;
        none)
            return 1 ;;
    esac
}

fw_proto_list() {
    case "$1" in
        tcp) echo tcp ;;
        udp) echo udp ;;
        *)   echo "tcp udp" ;;
    esac
}

# nft 初始化：建表建链，默认策略为“已部署端口放行”
fw_nft_init() {
    nft create table inet yuan 2>/dev/null
    nft create chain inet yuan input '{ type filter hook input priority 0; policy accept; }' 2>/dev/null
    # 基础放行：回环、已建立连接、SSH
    nft add rule inet yuan input iifname "lo" accept 2>/dev/null
    nft add rule inet yuan input ct state established,related accept 2>/dev/null
    nft add rule inet yuan input tcp dport 22 accept 2>/dev/null
}

fw_nft_save() {
    mkdir -p /etc/nftables.d
    nft list table inet yuan > /etc/nftables.d/yuan.nft 2>/dev/null
}

fw_ipt_save() {
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1
    elif [[ -d /etc/iptables ]]; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null
    fi
}

# 一键收紧：只保留 SSH + 各协议端口
fw_lockdown() {
    local be ports p proto
    be="$(fw_backend)"
    [[ "$be" == "none" ]] && { err "未检测到 nftables/iptables"; echo; pause; return 1; }

    warn "即将收紧防火墙：仅放行 SSH(22) 与已部署协议端口"
    confirm "继续吗？" || return 0

    # 收集已部署协议端口
    ports="22/tcp"
    for id in "${PROTOS[@]}"; do
        if "${id}_installed" 2>/dev/null; then
            p="$("${id}_port" 2>/dev/null)"
            [[ -n "$p" ]] && ports="$ports $p/both"
        fi
    done

    if [[ "$be" == "nft" ]]; then
        nft flush table inet yuan 2>/dev/null
        fw_nft_init
        for entry in $ports; do
            p="${entry%%/*}"; proto="${entry##*/}"
            for pr in $(fw_proto_list "$proto"); do
                [[ "$p" == "22" && "$pr" == "udp" ]] && continue
                nft add rule inet yuan input "$pr" dport "$p" accept 2>/dev/null
            done
        done
        fw_nft_save
    else
        for entry in $ports; do
            p="${entry%%/*}"; proto="${entry##*/}"
            for pr in $(fw_proto_list "$proto"); do
                [[ "$p" == "22" && "$pr" == "udp" ]] && continue
                iptables -C INPUT -p "$pr" --dport "$p" -j ACCEPT 2>/dev/null \
                    || iptables -I INPUT -p "$pr" --dport "$p" -j ACCEPT
            done
        done
        fw_ipt_save
    fi
    ok "防火墙已收紧，放行端口：$ports"
    echo; pause
}

fw_show() {
    local be
    be="$(fw_backend)"
    bold "—— 防火墙状态 ——"
    echo
    echo "后端：$be"
    echo
    case "$be" in
        nft)
            nft list table inet yuan 2>/dev/null || echo "(yuan 表不存在)"
            ;;
        iptables)
            iptables -L INPUT -n --line-numbers 2>/dev/null | head -30
            ;;
        none)
            warn "未安装 nftables/iptables"
            ;;
    esac
    echo
    echo "当前监听端口："
    ss -tuln 2>/dev/null | awk 'NR>1 {print "  " $1, $5}' | sort -u
    echo
    pause
}

fw_menu() {
    while true; do
        clear
        bold "—— 防火墙管理 ——"
        echo
        echo "后端：$(fw_backend)"
        echo
        echo " 1. 查看规则与监听端口"
        echo " 2. 一键收紧（仅放行 SSH + 协议端口）"
        echo " 3. 手动放行端口"
        echo " 0. 返回"
        echo
        local c port proto
        read -r -p "请选择 [0-3]: " c < /dev/tty
        case "$c" in
            1) fw_show ;;
            2) fw_lockdown ;;
            3)
                ask_input "端口" "" port
                valid_port "$port" || { err "端口不合法"; echo; pause; continue; }
                ask_input "协议 (tcp/udp/both)" "both" proto
                fw_allow "$port" "$proto" && ok "已放行 $port/$proto" || err "放行失败"
                echo; pause
                ;;
            0) return 0 ;;
            *) warn "无效选项"; sleep 1 ;;
        esac
    done
}
