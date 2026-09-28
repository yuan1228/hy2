#!/bin/bash
# ============================================================
# Yuan Toolbox · 网络工具：WARP 管理
# 基于 fscarmen/warp-sh（最成熟的 WARP 脚本），本面板做快捷入口
# WARP 用途：给纯 IPv6 机器加 IPv4 出口、解锁流媒体/ChatGPT
# ============================================================

WARP_MENU_URL="https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh"

warp_run() {
    ensure_cmd curl curl
    local tmp
    tmp="$(mktemp)"
    step "下载 WARP 管理脚本…"
    if ! curl -fsSL --max-time 60 "$WARP_MENU_URL" -o "$tmp"; then
        rm -f "$tmp"
        err "下载失败（GitLab 可能被墙，可给机器挂代理后重试）"
        echo; pause; return 1
    fi
    chmod +x "$tmp"
    bash "$tmp" "$@"
    rm -f "$tmp"
}

warp_menu() {
    while true; do
        clear
        bold "—— WARP 管理 ——"
        echo
        dim "WARP 可为 VPS 添加 Cloudflare 出口 IP，常用于："
        dim "  · 纯 IPv6 机器获得 IPv4 访问能力"
        dim "  · 解锁 ChatGPT / Netflix 等流媒体"
        echo
        # 快捷状态
        if ip -o link show warp 2>/dev/null | grep -q warp; then
            ok "WARP 接口：已存在"
        else
            dim "WARP 接口：未安装"
        fi
        echo
        echo "  1. 进入完整 WARP 菜单（fscarmen/warp-sh）"
        echo "  2. 快捷安装：WARP IPv4"
        echo "  3. 快捷安装：WARP IPv6"
        echo "  4. 快捷安装：WARP 双栈"
        echo "  5. 开关 WARP"
        echo "  6. 卸载 WARP"
        echo "  0. 返回"
        echo
        local c
        read -r -p "请选择 [0-6]: " c < /dev/tty
        case "$c" in
            1) warp_run ;;
            2) warp_run 4 ;;
            3) warp_run 6 ;;
            4) warp_run d ;;
            5) warp_run o ;;
            6) warp_run u ;;
            0) return 0 ;;
            *) warn "无效选项"; sleep 1 ;;
        esac
    done
}
