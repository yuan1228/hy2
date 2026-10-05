#!/bin/bash
# ============================================================
# Yuan VPS 工具箱 · 464XLAT 管理模块
# 纯 IPv6 VPS 访问 IPv4 网络的完整解决方案
# 架构：DNS64 + NAT64(PLAT) + CLAT(clatd)
# ============================================================

# 464XLAT 配置（外部 PLAT + 备选）
XLAT_DNS64_PRIMARY="2a00:1098:2b::1"
XLAT_PLAT_PRIMARY="2a00:1098:2b:0:0:1::/96"
XLAT_DNS64_BACKUP1="2001:67c:2b0::4"      # Trex 芬兰
XLAT_PLAT_BACKUP1="2001:67c:2b0:db32:0:1::/96"
XLAT_DNS64_BACKUP2="2001:67c:2960::64"    # level66 德国
XLAT_PLAT_BACKUP2="2001:67c:2960:6464::/96"

XLAT_RESOLV_BAK="/tmp/resolv.conf.xlat.bak"
XLAT_CLAT_CONF="/etc/clatd.conf"

# 检测是否为纯 IPv6 环境（无 IPv4 地址、无 IPv4 默认路由）
is_ipv6_only() {
    # 有 IPv4 地址则不是纯 v6
    ip -4 addr show scope global 2>/dev/null | grep -q "inet " && return 1
    # 有 IPv4 默认路由则不是纯 v6
    ip -4 route show default 2>/dev/null | grep -q . && return 1
    return 0
}

# 检测 464XLAT 是否运行中
xlat_running() {
    pgrep -f "clatd" >/dev/null 2>&1 && ip link show clat >/dev/null 2>&1
}

# 启动 464XLAT
xlat_start() {
    step "启动 464XLAT..."
    
    # 1. 安装 clatd（如未安装）
    if ! command -v clatd >/dev/null 2>&1; then
        step "安装 clatd..."
        apt-get update -qq && apt-get install -y -qq clatd || {
            err "clatd 安装失败"
            return 1
        }
        ok "clatd 安装完成"
    fi
    
    # 2. 备份 resolv.conf
    if [[ ! -f "$XLAT_RESOLV_BAK" ]]; then
        cp /etc/resolv.conf "$XLAT_RESOLV_BAK" 2>/dev/null
        dim "已备份 resolv.conf"
    fi
    
    # 3. 配置 DNS64
    printf 'nameserver %s\n' "$XLAT_DNS64_PRIMARY" > /etc/resolv.conf
    ok "DNS64 已配置 ($XLAT_DNS64_PRIMARY)"
    
    # 4. 配置 clatd
    printf 'plat-prefix=%s\n' "$XLAT_PLAT_PRIMARY" > "$XLAT_CLAT_CONF"
    ok "CLAT 已配置 (PLAT=$XLAT_PLAT_PRIMARY)"
    
    # 5. 启动 clatd
    pkill -f clatd 2>/dev/null; sleep 1
    setsid clatd >/tmp/clatd.log 2>&1 &
    sleep 3
    
    # 6. 设置 MTU
    ip link set clat mtu 1280 2>/dev/null
    
    if xlat_running; then
        ok "464XLAT 启动成功"
        return 0
    else
        err "464XLAT 启动失败，请查看 /tmp/clatd.log"
        return 1
    fi
}

# 停止 464XLAT
xlat_stop() {
    step "停止 464XLAT..."
    pkill -f clatd 2>/dev/null
    pkill -f tayga 2>/dev/null
    # 恢复 DNS
    if [[ -f "$XLAT_RESOLV_BAK" ]]; then
        cp "$XLAT_RESOLV_BAK" /etc/resolv.conf
        dim "resolv.conf 已恢复"
    fi
    ok "464XLAT 已停止"
}

# 删除清理 464XLAT（彻底卸载）
xlat_purge() {
    step "彻底清理 464XLAT..."
    xlat_stop
    # 删除网卡
    ip link set clat down 2>/dev/null
    # 删除路由残留
    ip route del default dev clat 2>/dev/null
    # 清理 nft
    nft flush table ip6 clatd 2>/dev/null
    nft delete table ip6 clatd 2>/dev/null
    # 卸载软件
    apt-get remove -y -qq clatd tayga 2>/dev/null
    rm -f "$XLAT_CLAT_CONF" /etc/tayga.conf
    rm -f /tmp/clatd.log "$XLAT_RESOLV_BAK"
    ok "464XLAT 已彻底清理，无残留"
}

# 查看状态 + 连通性测试
xlat_status() {
    echo "========== 464XLAT 状态 =========="
    if xlat_running; then
        ok "运行中"
        ip addr show clat 2>/dev/null | grep -E "inet |mtu" | head -3
        echo ""
        echo "--- PLAT 配置 ---"
        cat "$XLAT_CLAT_CONF" 2>/dev/null
        echo ""
        echo "--- DNS 配置 ---"
        cat /etc/resolv.conf | grep nameserver
    else
        warn "未运行"
    fi
    echo ""
    echo "========== 连通性测试 =========="
    echo -n "IPv6 直连: "
    curl -6 -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 https://cdn.jsdelivr.net 2>/dev/null || echo "失败"
    echo -n "IPv4 域名 (经464XLAT): "
    curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 15 https://github.com 2>/dev/null || echo "失败"
    echo -n "Telegram 裸IP (149.154.167.51): "
    curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 http://149.154.167.51 2>/dev/null || echo "失败"
    echo "（Telegram 返回 404 为正常，表示已连通）"
}

# 464XLAT 管理子菜单
xlat_menu() {
    while true; do
        clear
        echo "========== 464XLAT 管理 =========="
        if xlat_running; then
            echo "状态：运行中"
        else
            echo "状态：未运行"
        fi
        echo ""
        echo "1. 启动 464XLAT"
        echo "2. 停止 464XLAT"
        echo "3. 删除清理 464XLAT（彻底卸载）"
        echo "4. 查看状态 + 连通性测试"
        echo "0. 返回主菜单"
        echo ""
        read -rp "请选择 [0-4]: " choice
        case "$choice" in
            1) xlat_start; read -rp "按任意键继续..." -n1 ;;
            2) xlat_stop; read -rp "按任意键继续..." -n1 ;;
            3) xlat_purge; read -rp "按任意键继续..." -n1 ;;
            4) xlat_status; read -rp "按任意键继续..." -n1 ;;
            0) return ;;
            *) warn "无效选择" ;;
        esac
    done
}
