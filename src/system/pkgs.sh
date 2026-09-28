#!/bin/bash
# ============================================================
# Yuan Toolbox · 系统工具：常用组件安装
# 只装运维常用小工具，不碰建站/Docker 应用
# ============================================================

# 组件清单：名称|检测命令|包名(deb系)
PKGS=(
    "curl|curl|curl"
    "wget|wget|wget"
    "git|git|git"
    "vim|vim|vim"
    "htop|htop|htop"
    "tmux|tmux|tmux"
    "unzip|unzip|unzip"
    "mtr|mtr|mtr-tiny"
    "traceroute|traceroute|traceroute"
    "iperf3|iperf3|iperf3"
    "fail2ban|fail2ban|fail2ban"
    "dnsutils|nslookup|dnsutils"
)

pkgs_menu() {
    while true; do
        clear
        bold "—— 常用组件安装 ——"
        echo
        local i=1 entry name cmd st
        for entry in "${PKGS[@]}"; do
            name="${entry%%|*}"; cmd="$(cut -d'|' -f2 <<<"$entry")"
            if command -v "$cmd" >/dev/null 2>&1; then
                st="${C_GRN}已安装${C_RST}"
            else
                st="${C_DIM}未安装${C_RST}"
            fi
            printf "  %2d. %-12s %b\n" "$i" "$name" "$st"
            i=$((i+1))
        done
        echo
        echo "   a. 全部安装"
        echo "   0. 返回"
        echo
        local c
        read -r -p "输入序号安装（可多选用空格分隔，如 1 3 5）: " c < /dev/tty
        case "$c" in
            0) return 0 ;;
            a|A)
                pkgs_install_all ;;
            *)
                local n entry pkg cmd name
                for n in $c; do
                    if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#PKGS[@]} )); then
                        entry="${PKGS[$((n-1))]}"
                        name="${entry%%|*}"
                        cmd="$(cut -d'|' -f2 <<<"$entry")"
                        pkg="$(cut -d'|' -f3 <<<"$entry")"
                        ensure_cmd "$cmd" "$pkg" && ok "$name 就绪"
                    else
                        warn "忽略无效序号：$n"
                    fi
                done
                echo; pause
                ;;
        esac
    done
}

pkgs_install_all() {
    local entry pkg name cmd miss=()
    for entry in "${PKGS[@]}"; do
        name="${entry%%|*}"
        cmd="$(cut -d'|' -f2 <<<"$entry")"
        pkg="$(cut -d'|' -f3 <<<"$entry")"
        command -v "$cmd" >/dev/null 2>&1 || miss+=("$pkg")
    done
    if (( ${#miss[@]} == 0 )); then
        ok "全部组件已安装"; echo; pause; return 0
    fi
    warn "将安装：${miss[*]}"
    confirm "继续吗？" || return 0
    pkg_install "${miss[@]}" && ok "安装完成" || err "部分安装失败"
    echo; pause
}
