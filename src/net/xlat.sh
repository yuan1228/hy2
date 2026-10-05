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

XLAT_RESOLV_BAK="/etc/resolv.conf.xlat.bak"
XLAT_CLAT_CONF="/etc/clatd.conf"
XLAT_FAILOVER_SCRIPT="/usr/local/bin/nat64-failover.sh"
XLAT_FAILOVER_STATE="/var/run/nat64-current"
XLAT_FAILOVER_STATE_PERSIST="/etc/nat64-current"
XLAT_FAILOVER_LOG="/var/log/nat64-failover.log"
XLAT_FAILOVER_CRON="/etc/cron.d/nat64-failover"
XLAT_RESOLVED_MARK="/etc/.xlat-resolved-disabled"

# 安全写入 resolv.conf（先解除软链接，写后校验）
xlat_write_dns() {
    local dns="$1"
    # Bug 2 修复：Debian 13 默认 resolv.conf 是软链接，先解除
    [[ -L /etc/resolv.conf ]] && rm -f /etc/resolv.conf
    printf 'nameserver %s\n' "$dns" > /etc/resolv.conf
    grep -q "^nameserver $dns" /etc/resolv.conf || {
        err "DNS 写入失败"
        return 1
    }
}

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
STATE_PERSIST="/etc/nat64-current"
PROVIDERS=(
  "nat64.net|2a00:1098:2b::1|2a00:1098:2b:0:0:1::/96|2a00:1098:2b:0:0:1:808:808"
  "trex1|2001:67c:2b0::4|2001:67c:2b0:db32:0:1::/96|2001:67c:2b0:db32:0:1:808:808"
  "trex2|2001:67c:2b0::6|2001:67c:2b0:db32::/96|2001:67c:2b0:db32:0:808:808"
  "level66|2001:67c:2960::64|2001:67c:2960:6464::/96|2001:67c:2960:6464::808:808"
)
# Bug 12 修复：日志超过 1MB 时轮转
if [[ -f "$LOG" && $(stat -c%s "$LOG" 2>/dev/null || echo 0) -gt 1048576 ]]; then
  mv "$LOG" "$LOG.1" 2>/dev/null
fi
log() { echo "[$(date '+%F %T')] $1" | tee -a "$LOG"; }
# Bug 1 修复：状态持久化到 /etc，重启不丢失
current_idx=0
if [[ -f "$STATE_PERSIST" ]]; then
  current_idx=$(cat "$STATE_PERSIST" 2>/dev/null || echo 0)
  echo "$current_idx" > "$STATE" 2>/dev/null
elif [[ -f "$STATE" ]]; then
  current_idx=$(cat "$STATE" 2>/dev/null || echo 0)
fi
test_plat() { ping -6 -c 3 -W 2 "$1" >/dev/null 2>&1; }
# Bug 10 修复：同时检查 DNS64 是否能合成记录
test_dns64() {
  local dns64="$1"
  dig +short +time=3 +tries=1 AAAA github.com "@$dns64" 2>/dev/null | grep -q ":"
}
switch_to() {
  local idx=$1
  IFS='|' read -r name dns64 prefix testip <<< "${PROVIDERS[$idx]}"
  log "切换到 $name (DNS64=$dns64, PLAT=$prefix)"
  # 解除软链接后写入 DNS
  [[ -L /etc/resolv.conf ]] && rm -f /etc/resolv.conf
  printf 'nameserver %s\n' "$dns64" > /etc/resolv.conf
  printf 'plat-prefix=%s\n' "$prefix" > /etc/clatd.conf
  # Bug 3 修复：走 systemd 重启，避免与 Restart=always 竞态
  if pidof systemd >/dev/null 2>&1; then
    systemctl restart clatd 2>/dev/null
    # 轮询等待网卡就绪，最多 20 秒
    local waited=0
    while [[ $waited -lt 20 ]]; do
      ip link show clat >/dev/null 2>&1 && pgrep -f clatd >/dev/null && break
      sleep 1
      waited=$((waited+1))
    done
  else
    pkill -f clatd; sleep 2
    setsid clatd >/tmp/clatd.log 2>&1 &
    sleep 3
  fi
  ip link set clat mtu 1280 2>/dev/null
  if test_plat "$testip" && test_dns64 "$dns64"; then
    echo "$idx" > "$STATE" 2>/dev/null
    echo "$idx" > "$STATE_PERSIST" 2>/dev/null
    log "切换成功，$name 工作正常"
    return 0
  else
    log "切换后 $name 仍不可用"
    return 1
  fi
}
IFS='|' read -r cur_name cur_dns cur_prefix cur_testip <<< "${PROVIDERS[$current_idx]}"
log "检测当前 PLAT ($cur_name)..."
if test_plat "$cur_testip" && test_dns64 "$cur_dns"; then
  log "当前 PLAT 正常，无需切换"
  exit 0
fi
log "当前 PLAT ($cur_name) 故障，开始故障切换..."
for i in 0 1 2 3; do
  [ "$i" -eq "$current_idx" ] && continue
  IFS='|' read -r name dns64 prefix testip <<< "${PROVIDERS[$i]}"
  log "尝试 $name..."
  if test_plat "$testip" && test_dns64 "$dns64"; then
    switch_to "$i" && exit 0
  else
    log "$name 不可用，跳过"
  fi
done
log "所有 PLAT 均不可用！"
exit 1
FOEOF
    chmod +x "$XLAT_FAILOVER_SCRIPT"
    echo "*/5 * * * * root $XLAT_FAILOVER_SCRIPT" > "$XLAT_FAILOVER_CRON"
    # Bug 11 修复：状态文件不存在时才初始化，不丢弃历史切换结果
    if [[ ! -f "$XLAT_FAILOVER_STATE_PERSIST" && ! -f "$XLAT_FAILOVER_STATE" ]]; then
        echo "0" > "$XLAT_FAILOVER_STATE" 2>/dev/null
        echo "0" > "$XLAT_FAILOVER_STATE_PERSIST" 2>/dev/null
    fi
    dim "已安装 PLAT 自动故障切换（每5分钟检测）"
}

# 卸载 NAT64 自动故障切换
xlat_failover_remove() {
    rm -f "$XLAT_FAILOVER_SCRIPT" "$XLAT_FAILOVER_CRON" "$XLAT_FAILOVER_STATE" "$XLAT_FAILOVER_STATE_PERSIST"
    dim "已卸载 PLAT 自动故障切换"
}

# 查看当前使用的 PLAT
xlat_current_provider() {
    local idx=0
    # Bug 16 修复：优先读持久化状态，重启后也不误导
    if [[ -f "$XLAT_FAILOVER_STATE_PERSIST" ]]; then
        idx=$(cat "$XLAT_FAILOVER_STATE_PERSIST" 2>/dev/null || echo 0)
    elif [[ -f "$XLAT_FAILOVER_STATE" ]]; then
        idx=$(cat "$XLAT_FAILOVER_STATE" 2>/dev/null || echo 0)
    fi
    IFS='|' read -r name dns64 prefix testip <<< "${XLAT_PROVIDERS[$idx]}"
    echo "$name"
}

# 启动 464XLAT
xlat_start() {
    step "启动 464XLAT..."

    # Bug 4 修复：非 systemd 系统走回退路径
    if ! pidof systemd >/dev/null 2>&1 || ! command -v systemctl >/dev/null 2>&1; then
        xlat_start_nosystemd
        return $?
    fi

    # 1. 安装 clatd（如未安装）
    if ! command -v clatd >/dev/null 2>&1; then
        step "安装 clatd..."
        apt-get update -qq && apt-get install -y -qq clatd || {
            err "clatd 安装失败"
            return 1
        }
        ok "clatd 安装完成"
    fi

    # Bug 6 修复：tayga 是 NAT64 网关服务端，CLAT 客户端用不上，禁用避免开机噪音
    systemctl disable --now tayga 2>/dev/null
    dim "已禁用 tayga（CLAT 不需要）"

    # 2. 备份 resolv.conf（Bug 5 修复：从 /tmp 移到 /etc，重启不丢失）
    if [[ ! -f "$XLAT_RESOLV_BAK" ]]; then
        # 先解除软链接再备份，确保拿到真实内容
        if [[ -L /etc/resolv.conf ]]; then
            cp --remove-destination "$(readlink /etc/resolv.conf)" "$XLAT_RESOLV_BAK" 2>/dev/null \
                || cp /etc/resolv.conf "$XLAT_RESOLV_BAK" 2>/dev/null
        else
            cp /etc/resolv.conf "$XLAT_RESOLV_BAK" 2>/dev/null
        fi
        dim "已备份 resolv.conf"
    fi

    # 3. 停用 systemd-resolved（防止重启后 DNS 被改回 127.0.0.53）
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        systemctl stop systemd-resolved 2>/dev/null
        systemctl disable systemd-resolved 2>/dev/null
        touch "$XLAT_RESOLVED_MARK"
        dim "已停用 systemd-resolved（DNS 不会被重置）"
    fi

    # 4. 配置 DNS64（Bug 2 修复：用安全写入函数处理软链接）
    xlat_write_dns "$XLAT_DNS64_PRIMARY" || return 1
    ok "DNS64 已配置 ($XLAT_DNS64_PRIMARY)"

    # 5. 配置 clatd
    printf 'plat-prefix=%s\n' "$XLAT_PLAT_PRIMARY" > "$XLAT_CLAT_CONF"
    ok "CLAT 已配置 (PLAT=$XLAT_PLAT_PRIMARY)"

    # 6. 创建 clatd 启动包装脚本（等网卡就绪再设 MTU，避免开机竞态）
    cat > /usr/local/bin/clatd-start.sh << 'SHEOF'
#!/bin/bash
# clatd 启动包装：等网卡就绪再设 MTU（由 yuan 工具箱安装）
pkill -f "/usr/sbin/clatd" 2>/dev/null
sleep 1
/usr/sbin/clatd &
CLAT_PID=$!
for i in $(seq 1 15); do
  ip link show clat >/dev/null 2>&1 && break
  sleep 1
done
ip link set clat mtu 1280 2>/dev/null
wait $CLAT_PID
SHEOF
    chmod +x /usr/local/bin/clatd-start.sh

    # 7. 创建 DNS 恢复脚本（根据当前 PLAT 前缀找对应的 DNS64，避免 failover 切换后重启 mismatch）
    cat > /usr/local/bin/clatd-dns.sh << 'DNSEOF'
#!/bin/bash
# 根据 /etc/clatd.conf 的 PLAT 前缀，还原对应的 DNS64（由 yuan 工具箱安装）
PLAT="$(grep -oE '^plat-prefix=[^[:space:]]+' /etc/clatd.conf 2>/dev/null | cut -d= -f2)"
case "$PLAT" in
  "2a00:1098:2b:0:0:1::/96")      DNS="2a00:1098:2b::1" ;;
  "2001:67c:2b0:db32:0:1::/96")   DNS="2001:67c:2b0::4" ;;
  "2001:67c:2b0:db32::/96")       DNS="2001:67c:2b0::6" ;;
  "2001:67c:2960:6464::/96")      DNS="2001:67c:2960::64" ;;
  *)                              DNS="2a00:1098:2b::1" ;;
esac
# Bug 2 修复：先解除软链接再写入
[[ -L /etc/resolv.conf ]] && rm -f /etc/resolv.conf
printf 'nameserver %s\n' "$DNS" > /etc/resolv.conf
DNSEOF
    chmod +x /usr/local/bin/clatd-dns.sh

    # 8. 创建 systemd 开机自启服务（ExecStartPre 每次启动按当前 PLAT 还原 DNS）
    cat > /etc/systemd/system/clatd.service << SVCEOF
[Unit]
Description=464XLAT CLAT daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/usr/local/bin/clatd-dns.sh
ExecStart=/usr/local/bin/clatd-start.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload 2>/dev/null
    systemctl enable clatd 2>/dev/null
    systemctl restart clatd 2>/dev/null
    dim "已设置开机自启（DNS+网卡开机自动恢复）"

    # 8. 安装 PLAT 自动故障切换
    xlat_failover_install

    # Bug 7 修复：轮询等待最多 20 秒，而非固定 sleep 5
    local waited=0
    while [[ $waited -lt 20 ]]; do
        xlat_running && break
        sleep 1
        waited=$((waited+1))
    done

    if xlat_running; then
        # Bug 8 修复：验证端到端连通，而不仅是进程+网卡
        if curl -s -o /dev/null --max-time 10 http://149.154.167.51 2>/dev/null; then
            ok "464XLAT 启动成功（已设开机自启 + PLAT自动切换，IPv4 连通性验证通过）"
        else
            warn "464XLAT 进程已启动，但 IPv4 连通性验证失败，请检查 PLAT"
        fi
        return 0
    else
        # Bug 9 修复：指向正确的日志位置
        err "464XLAT 启动失败，请查看 journalctl -u clatd -n 50 --no-pager"
        return 1
    fi
}

# 非 systemd 系统的回退启动（Bug 4 修复：Alpine/OpenRC）
xlat_start_nosystemd() {
    step "检测到非 systemd 系统，使用直接启动模式…"
    pkill -f "/usr/sbin/clatd" 2>/dev/null; sleep 1
    setsid /usr/sbin/clatd >/tmp/clatd.log 2>&1 &
    local waited=0
    while [[ $waited -lt 15 ]]; do
        xlat_running && break
        sleep 1
        waited=$((waited+1))
    done
    ip link set clat mtu 1280 2>/dev/null
    if xlat_running; then
        ok "464XLAT 启动成功（非 systemd 模式，无开机自启）"
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
    else
        # Bug 5 修复：备份丢失时也要清理 DNS64 残留，避免断网
        warn "DNS 备份丢失，清理 DNS64 残留…"
        grep -v "2a00:1098:2b::1\|2001:67c:2b0::\|2001:67c:2960::64" /etc/resolv.conf > /tmp/resolv.tmp 2>/dev/null \
            && mv /tmp/resolv.tmp /etc/resolv.conf
    fi
    # Bug 13 修复：用标记文件判断是否停用过 resolved，而非猜测备份内容
    if [[ -f "$XLAT_RESOLVED_MARK" ]]; then
        systemctl enable systemd-resolved 2>/dev/null
        systemctl start systemd-resolved 2>/dev/null
        rm -f "$XLAT_RESOLVED_MARK"
        dim "systemd-resolved 已恢复"
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
    rm -f /usr/local/bin/clatd-start.sh /usr/local/bin/clatd-dns.sh
    rm -f /tmp/clatd.log "$XLAT_RESOLV_BAK" "$XLAT_RESOLVED_MARK"
    rm -f "$XLAT_FAILOVER_LOG" "$XLAT_FAILOVER_STATE_PERSIST"
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
