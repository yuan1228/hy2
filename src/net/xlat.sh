#!/bin/bash
# ============================================================
# Yuan VPS 工具箱 · 464XLAT 管理模块
# 纯 IPv6 VPS 访问 IPv4 网络的完整解决方案
# 架构：DNS64 + NAT64(PLAT) + CLAT(clatd)
# ============================================================

# 464XLAT 配置（4 路 PLAT 自动故障切换）
# 格式：名称|DNS64|PLAT前缀|测试IP(8.8.8.8经PLAT翻译)
XLAT_PROVIDERS=(
  "nat64.net|2a00:1098:2b::1|2a00:1098:2b:0:0:1::/96|2a00:1098:2b:0:0:1:808:808"
  "trex1|2001:67c:2b0::4|2001:67c:2b0:db32:0:1::/96|2001:67c:2b0:db32:0:1:808:808"
  "trex2|2001:67c:2b0::6|2001:67c:2b0:db32::/96|2001:67c:2b0:db32:0:808:808"
  "level66|2001:67c:2960::64|2001:67c:2960:6464::/96|2001:67c:2960:6464::808:808"
)
# 兼容旧变量名（默认用第一个）
XLAT_DNS64_PRIMARY="2a00:1098:2b::1"
XLAT_PLAT_PRIMARY="2a00:1098:2b:0:0:1::/96"

XLAT_RESOLV_BAK="/tmp/resolv.conf.xlat.bak"
XLAT_CLAT_CONF="/etc/clatd.conf"
XLAT_FAILOVER_SCRIPT="/usr/local/bin/nat64-failover.sh"
XLAT_FAILOVER_STATE="/var/run/nat64-current"
XLAT_FAILOVER_LOG="/var/log/nat64-failover.log"
XLAT_FAILOVER_CRON="/etc/cron.d/nat64-failover"

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

# 安装 NAT64 自动故障切换（每5分钟检测，故障自动切下一个）
xlat_failover_install() {
    cat > "$XLAT_FAILOVER_SCRIPT" << 'FOEOF'
#!/bin/bash
# NAT64/PLAT 自动故障切换（由 yuan 工具箱安装）
LOG="/var/log/nat64-failover.log"
STATE="/var/run/nat64-current"
PROVIDERS=(
  "nat64.net|2a00:1098:2b::1|2a00:1098:2b:0:0:1::/96|2a00:1098:2b:0:0:1:808:808"
  "trex1|2001:67c:2b0::4|2001:67c:2b0:db32:0:1::/96|2001:67c:2b0:db32:0:1:808:808"
  "trex2|2001:67c:2b0::6|2001:67c:2b0:db32::/96|2001:67c:2b0:db32:0:808:808"
  "level66|2001:67c:2960::64|2001:67c:2960:6464::/96|2001:67c:2960:6464::808:808"
)
log() { echo "[$(date '+%F %T')] $1" | tee -a "$LOG"; }
current_idx=0
[ -f "$STATE" ] && current_idx=$(cat "$STATE")
test_plat() { ping -6 -c 3 -W 2 "$1" >/dev/null 2>&1; }
switch_to() {
  local idx=$1
  IFS='|' read -r name dns64 prefix testip <<< "${PROVIDERS[$idx]}"
  log "切换到 $name (DNS64=$dns64, PLAT=$prefix)"
  printf 'nameserver %s\n' "$dns64" > /etc/resolv.conf
  printf 'plat-prefix=%s\n' "$prefix" > /etc/clatd.conf
  pkill -f clatd; sleep 2
  setsid clatd >/tmp/clatd.log 2>&1 &
  sleep 3
  ip link set clat mtu 1280 2>/dev/null
  if test_plat "$testip"; then
    echo "$idx" > "$STATE"
    log "切换成功，$name 工作正常"
    return 0
  else
    log "切换后 $name 仍不可用"
    return 1
  fi
}
IFS='|' read -r cur_name cur_dns cur_prefix cur_testip <<< "${PROVIDERS[$current_idx]}"
log "检测当前 PLAT ($cur_name)..."
if test_plat "$cur_testip"; then
  log "当前 PLAT 正常，无需切换"
  exit 0
fi
log "当前 PLAT ($cur_name) 故障，开始故障切换..."
for i in 0 1 2 3; do
  [ "$i" -eq "$current_idx" ] && continue
  IFS='|' read -r name dns64 prefix testip <<< "${PROVIDERS[$i]}"
  log "尝试 $name..."
  if test_plat "$testip"; then
    switch_to "$i" && exit 0
  else
    log "$name 的 PLAT 也不可达，跳过"
  fi
done
log "所有 PLAT 均不可用！"
exit 1
FOEOF
    chmod +x "$XLAT_FAILOVER_SCRIPT"
    echo "*/5 * * * * root $XLAT_FAILOVER_SCRIPT" > "$XLAT_FAILOVER_CRON"
    echo "0" > "$XLAT_FAILOVER_STATE" 2>/dev/null
    dim "已安装 PLAT 自动故障切换（每5分钟检测）"
}

# 卸载 NAT64 自动故障切换
xlat_failover_remove() {
    rm -f "$XLAT_FAILOVER_SCRIPT" "$XLAT_FAILOVER_CRON" "$XLAT_FAILOVER_STATE"
    dim "已卸载 PLAT 自动故障切换"
}

# 查看当前使用的 PLAT
xlat_current_provider() {
    local idx=0
    [[ -f "$XLAT_FAILOVER_STATE" ]] && idx=$(cat "$XLAT_FAILOVER_STATE" 2>/dev/null)
    IFS='|' read -r name dns64 prefix testip <<< "${XLAT_PROVIDERS[$idx]}"
    echo "$name"
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

    # 7. 创建 systemd 开机自启服务
    cat > /etc/systemd/system/clatd.service << 'SVCEOF'
[Unit]
Description=464XLAT CLAT daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/sbin/clatd
ExecStartPost=/bin/sleep 2
ExecStartPost=/sbin/ip link set clat mtu 1280
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload 2>/dev/null
    systemctl enable clatd 2>/dev/null
    dim "已设置开机自启"

    # 8. 安装 PLAT 自动故障切换
    xlat_failover_install

    if xlat_running; then
        ok "464XLAT 启动成功（已设开机自启 + PLAT自动切换）"
        return 0
    else
        err "464XLAT 启动失败，请查看 /tmp/clatd.log"
        return 1
    fi
}

# 停止 464XLAT
xlat_stop() {
    step "停止 464XLAT..."
    systemctl stop clatd 2>/dev/null
    systemctl disable clatd 2>/dev/null
    pkill -f clatd 2>/dev/null
    pkill -f tayga 2>/dev/null
    xlat_failover_remove
    # 恢复 DNS
    if [[ -f "$XLAT_RESOLV_BAK" ]]; then
        cp "$XLAT_RESOLV_BAK" /etc/resolv.conf
        dim "resolv.conf 已恢复"
    fi
    ok "464XLAT 已停止（开机自启已关闭）"
}

# 删除清理 464XLAT（彻底卸载）
xlat_purge() {
    step "彻底清理 464XLAT..."
    xlat_stop
    # 删除 systemd 服务
    rm -f /etc/systemd/system/clatd.service
    systemctl daemon-reload 2>/dev/null
    # 删除网卡
    ip link set clat down 2>/dev/null
    ip link delete clat 2>/dev/null
    # 删除路由残留
    ip route del default dev clat 2>/dev/null
    # 清理 nft
    nft flush table ip6 clatd 2>/dev/null
    nft delete table ip6 clatd 2>/dev/null
    # 卸载软件
    apt-get remove -y -qq clatd tayga 2>/dev/null
    rm -f "$XLAT_CLAT_CONF" /etc/tayga.conf
    rm -f /tmp/clatd.log "$XLAT_RESOLV_BAK"
    rm -f "$XLAT_FAILOVER_LOG"
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
        echo ""
        echo "  464XLAT 是什么？"
        echo "  纯 IPv6 的 VPS 无法直接访问 IPv4 网络（如 GitHub、Telegram）。"
        echo "  464XLAT 由三部分组成，一键自动部署："
        echo "    1. DNS64：将 IPv4 域名解析成特殊的 IPv6 地址"
        echo "    2. NAT64(PLAT)：公网翻译网关，把 IPv6 流量转成 IPv4"
        echo "    3. CLAT(clatd)：本机翻译器，让程序无感知使用 IPv4"
        echo ""
        echo "  什么时候用？"
        echo "    - 纯 IPv6 VPS 上装节点、下载 GitHub 文件"
        echo "    - 让 HY2/VLESS 节点能访问 IPv4 目标"
        echo "    - 不需要时可随时停止/清理，不留残留"
        echo ""
        if xlat_running; then
            echo "  当前状态：运行中（当前 PLAT：$(xlat_current_provider)）"
        else
            echo "  当前状态：未运行"
        fi
        if [[ -f "$XLAT_FAILOVER_CRON" ]]; then
            echo "  故障切换：已启用（每5分钟检测，4路自动切换）"
        fi
        echo ""
        echo "1. 启动 464XLAT（含 DNS64+NAT64+CLAT+自动切换）"
        echo "2. 停止 464XLAT"
        echo "3. 删除清理 464XLAT（彻底卸载）"
        echo "4. 查看状态 + 连通性测试"
        echo "5. 查看故障切换日志"
        echo "0. 返回主菜单"
        echo ""
        read -rp "请选择 [0-5]: " choice
        case "$choice" in
            1) xlat_start; read -rp "按任意键继续..." -n1 ;;
            2) xlat_stop; read -rp "按任意键继续..." -n1 ;;
            3) xlat_purge; read -rp "按任意键继续..." -n1 ;;
            4) xlat_status; read -rp "按任意键继续..." -n1 ;;
            5) tail -30 "$XLAT_FAILOVER_LOG" 2>/dev/null || warn "暂无切换日志"; read -rp "按任意键继续..." -n1 ;;
            0) return ;;
            *) warn "无效选择" ;;
        esac
    done
}
