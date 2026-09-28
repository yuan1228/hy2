#!/bin/bash
# ============================================================
# Yuan Panel · 主菜单
# 顶部状态仪表盘 + 协议子菜单 + 系统工具
# ============================================================

# 协议注册表：id 顺序即菜单顺序
PROTOS=(hy2 vless trojan ss)

# id -> 显示名 / 模块文件
proto_name() {
    case "$1" in
        hy2)    echo "Hysteria2" ;;
        vless)  echo "VLESS+REALITY" ;;
        trojan) echo "Trojan" ;;
        ss)     echo "Shadowsocks" ;;
    esac
}

load_modules() {
    # shellcheck disable=SC1091
    source "$YUAN_ROOT/src/protocols/hysteria2.sh"
    source "$YUAN_ROOT/src/protocols/vless.sh"
    source "$YUAN_ROOT/src/protocols/trojan.sh"
    source "$YUAN_ROOT/src/protocols/shadowsocks.sh"
    source "$YUAN_ROOT/src/system/tuning.sh"
    source "$YUAN_ROOT/src/system/firewall.sh"
    source "$YUAN_ROOT/src/system/security.sh"
    source "$YUAN_ROOT/src/update.sh"
}

# 状态点：● 运行中  ◐ 已安装未运行  ○ 未安装
proto_dot() {
    local id="$1"
    if "${id}_active" 2>/dev/null; then
        printf "${C_GRN}●${C_RST}"
    elif "${id}_installed" 2>/dev/null; then
        printf "${C_YLW}◐${C_RST}"
    else
        printf "${C_DIM}○${C_RST}"
    fi
}

proto_state_text() {
    local id="$1" port
    if "${id}_active" 2>/dev/null; then
        port="$("${id}_port" 2>/dev/null)"
        printf "${C_GRN}运行中${C_RST} :%s" "$port"
    elif "${id}_installed" 2>/dev/null; then
        printf "${C_YLW}已停止${C_RST}"
    else
        printf "${C_DIM}未安装${C_RST}"
    fi
}

draw_header() {
    sysinfo
    clear
    echo -e "${C_BLD}============================================================${C_RST}"
    echo -e "  ${C_CYN}${C_BLD}Yuan Panel${C_RST} ${C_DIM}v$YUAN_VERSION · 多协议节点管理${C_RST}"
    echo -e "  ${C_DIM}$SYS_OS $SYS_VER · $SYS_ARCH · 虚拟化 $SYS_VIRT${C_RST}"
    echo -e "${C_BLD}------------------------------------------------------------${C_RST}"
    local id
    for id in "${PROTOS[@]}"; do
        printf "  %b %-14s %b\n" "$(proto_dot "$id")" "$(proto_name "$id")" "$(proto_state_text "$id")"
    done
    echo -e "${C_BLD}============================================================${C_RST}"
}

proto_menu() {
    local id="$1" name
    name="$(proto_name "$id")"
    while true; do
        clear
        bold "—— $name 管理 ——"
        echo
        echo -e "状态：$(proto_state_text "$id")"
        echo
        echo " 1. 安装 / 重新部署"
        echo " 2. 查看节点链接"
        echo " 3. 查看运行状态"
        echo " 4. 重启服务"
        echo " 5. 查看运行日志"
        echo " 6. 卸载"
        echo " 0. 返回主菜单"
        echo
        local c
        read -r -p "请选择 [0-6]: " c < /dev/tty
        case "$c" in
            1) "${id}_deploy" ;;
            2) "${id}_link" ;;
            3) "${id}_status" ;;
            4) "${id}_restart" ;;
            5) "${id}_logs" ;;
            6) "${id}_uninstall" ;;
            0) return 0 ;;
            *) warn "无效选项"; sleep 1 ;;
        esac
    done
}

show_all_links() {
    clear
    bold "—— 全部节点链接 ——"
    echo
    local id found=0 link
    for id in "${PROTOS[@]}"; do
        link=""
        [[ -f "$YUAN_CONF/$id/link.txt" ]] && link="$(cat "$YUAN_CONF/$id/link.txt")"
        # 兼容 v1 hysteria 旧路径
        [[ -z "$link" && "$id" == "hy2" && -f /etc/hysteria/share_link.txt ]] \
            && link="$(cat /etc/hysteria/share_link.txt)"
        if [[ -n "$link" ]]; then
            found=1
            echo -e "${C_BLD}$(proto_name "$id")${C_RST}"
            echo "$link"
            echo
        fi
    done
    (( found )) || warn "暂无已部署的节点"
    pause
}

main_menu() {
    load_modules
    local c id i
    while true; do
        draw_header
        echo
        echo "  协议管理："
        i=1
        for id in "${PROTOS[@]}"; do
            printf "   %d. %s\n" "$i" "$(proto_name "$id")"
            i=$((i+1))
        done
        echo
        echo "  系统工具："
        echo "   5. 网络调优 (BBR)"
        echo "   6. 防火墙管理"
        echo "   7. 安全检查"
        echo "   8. 查看全部节点链接"
        echo "   9. 检查更新"
        echo "   0. 退出"
        echo
        read -r -p "请选择 [0-9]: " c < /dev/tty
        case "$c" in
            1|2|3|4) proto_menu "${PROTOS[$((c-1))]}" ;;
            5) tuning_menu ;;
            6) fw_menu ;;
            7) sec_run ;;
            8) show_all_links ;;
            9) update_panel ;;
            0) echo "再见！"; exit 0 ;;
            *) warn "无效选项"; sleep 1 ;;
        esac
    done
}
