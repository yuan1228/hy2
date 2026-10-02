#!/bin/bash
# ============================================================
# Yuan VPS 工具箱 · 系统模块：网络调优（BBR / 内核参数）
# ============================================================

tuning_menu() {
    while true; do
        clear
        bold "—— 系统网络调优 ——"
        echo
        echo "当前拥塞算法：$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 未知)"
        echo "当前队列算法：$(sysctl -n net.core.default_qdisc 2>/dev/null || echo 未知)"
        echo
        echo " 1. 启用 BBR + FQ（推荐）"
        echo " 2. 启用 BBR + CAKE"
        echo " 3. 恢复默认（cubic）"
        echo " 4. 应用通用优化参数（缓冲区/ backlog）"
        echo " 0. 返回"
        echo
        local c
        read -r -p "请选择 [0-4]: " c < /dev/tty
        case "$c" in
            1) tuning_set_bbr fq ;;
            2) tuning_set_bbr cake ;;
            3) tuning_reset ;;
            4) tuning_general ;;
            0) return 0 ;;
            *) warn "无效选项"; sleep 1 ;;
        esac
    done
}

tuning_check_env() {
    sysinfo
    if [[ "$SYS_VIRT" == "openvz" || "$SYS_VIRT" == "lxc" ]]; then
        warn "检测到容器虚拟化（$SYS_VIRT），通常无权修改内核参数，配置可能不生效"
        confirm "仍要继续吗？" || return 1
    fi
    # Debian/Ubuntu 上 bbr 是 tcp_bbr 内核模块，默认未加载；
    # tcp_available_congestion_control 只列出已加载的算法，不先 modprobe 会误判为不支持
    modprobe tcp_bbr 2>/dev/null
    if ! sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
        err "当前内核不支持 BBR"
        echo; pause; return 1
    fi
    return 0
}

tuning_set_bbr() {
    local qdisc="$1"
    tuning_check_env || return 0

    # 清理旧配置（锚定行首，避免误删注释）
    sed -i '/^net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/^net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

    if [[ "$qdisc" == "cake" ]]; then
        if ! modprobe sch_cake 2>/dev/null && [[ ! -d /sys/module/sch_cake ]]; then
            warn "未找到 sch_cake 模块，自动改用 FQ"
            qdisc="fq"
        fi
    fi
    {
        echo "net.core.default_qdisc=$qdisc"
        echo "net.ipv4.tcp_congestion_control=bbr"
    } >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1

    echo "当前拥塞算法：$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    echo "当前队列算法：$(sysctl -n net.core.default_qdisc 2>/dev/null)"
    ok "BBR 已启用"
    echo; pause
}

tuning_reset() {
    sed -i '/^net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/^net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
    sysctl -p >/dev/null 2>&1
    ok "已恢复默认拥塞算法（cubic）"
    echo; pause
}

# 通用优化：收发缓冲区、backlog、MTU 探测等（容器安全，可回滚）
tuning_general() {
    local conf="/etc/sysctl.d/99-yuan-tuning.conf"
    cat > "$conf" <<'EOF'
# Yuan VPS 工具箱 通用网络优化
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
EOF
    chmod 644 "$conf"
    sysctl --system >/dev/null 2>&1
    ok "通用优化参数已写入 $conf 并生效"
    dim  "如需回滚，删除该文件后执行 sysctl --system"
    echo; pause
}
