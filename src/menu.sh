#!/bin/bash
# ============================================================
# Yuan VPS 工具箱 · 主菜单
# 风格参考 eooce/ssh_tool：VPS 常用工具合集，不含建站
# ============================================================

# 协议注册表（节点搭建区）
PROTOS=(hy2 vless trojan ss)

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
    source "$YUAN_ROOT/src/system/info.sh"
    source "$YUAN_ROOT/src/system/maintenance.sh"
    source "$YUAN_ROOT/src/system/tuning.sh"
    source "$YUAN_ROOT/src/system/firewall.sh"
    source "$YUAN_ROOT/src/system/security.sh"
    source "$YUAN_ROOT/src/system/pkgs.sh"
    source "$YUAN_ROOT/src/net/warp.sh"
    source "$YUAN_ROOT/src/net/xlat.sh"
    source "$YUAN_ROOT/src/net/tcpquality.sh"
    source "$YUAN_ROOT/src/net/nodequality.sh"
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
    echo -e "  ${C_CYN}${C_BLD}Yuan VPS 工具箱${C_RST} ${C_DIM}v$YUAN_VERSION${C_RST}"
    echo -e "  ${C_DIM}$SYS_OS $SYS_VER · $SYS_ARCH · $SYS_VIRT${C_RST}"
    echo -e "${C_BLD}------------------------------------------------------------${C_RST}"
    local id
    for id in "${PROTOS[@]}"; do
        printf "  %b %-14s %b\n" "$(proto_dot "$id")" "$(proto_name "$id")" "$(proto_state_text "$id")"
    done
    echo -e "${C_BLD}============================================================${C_RST}"
}

draw_menu() {
    echo
    echo -e " ${C_BLD}节点搭建${C_RST}"
    echo -e " ${C_GRN} 1. Hysteria2 管理         2. VLESS+REALITY 管理${C_RST}"
    echo -e " ${C_GRN} 3. Trojan 管理            4. Shadowsocks 管理${C_RST}"
    echo -e " ${C_GRN} 5. WARP 管理              6. 464XLAT 管理${C_RST}"
    echo -e " ${C_BLD}------------------------------------------------------------${C_RST}"
    echo -e " ${C_BLD}系统工具${C_RST}"
    echo -e " ${C_GRN} 7. 本机信息               8. 系统更新${C_RST}"
    echo -e " ${C_GRN} 9. 系统清理              10. BBR / 网络调优${C_RST}"
    echo -e " ${C_GRN}11. 防火墙管理            12. 安全检查${C_RST}"
    echo -e " ${C_GRN}13. 常用组件安装          14. 全部节点链接${C_RST}"
    echo -e " ${C_BLD}------------------------------------------------------------${C_RST}"
    echo -e " ${C_BLD}网络测试${C_RST} ${C_DIM}(每次运行前自动检查上游更新)${C_RST}"
    echo -e " ${C_GRN}15. TcpQuality${C_RST} ${C_DIM}TCP 三网质量检测${C_RST}"
    echo -e " ${C_GRN}16. NodeQuality${C_RST} ${C_DIM}综合体检：性能+IP质量+网络质量${C_RST}"
    echo -e " ${C_BLD}------------------------------------------------------------${C_RST}"
    echo -e " ${C_YLW}00. 检查更新${C_RST}              ${C_RED}88. 退出${C_RST}"
    echo -e " ${C_RED}99. 卸载工具箱${C_RST}"
    echo -e "${C_BLD}============================================================${C_RST}"
    echo
}

# 部署方式选择：一键（全默认）或自定义（逐项确认）
proto_deploy() {
    local id="$1"
    echo
    echo "  1. 一键部署（端口/密码/SNI 全用默认值）"
    echo "  2. 自定义部署（逐项设置）"
    echo "  0. 返回"
    echo
    local c
    read -r -p "请选择 [0-2]: " c < /dev/tty
    case "$c" in
        1) QUICK=1 "${id}_deploy"; QUICK=0 ;;
        2) "${id}_deploy" ;;
        0) return 0 ;;
        *) warn "无效选项"; sleep 1 ;;
    esac
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
            1) proto_deploy "$id" ;;
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

# 一键卸载工具箱本身
uninstall_panel() {
    echo
    warn "即将卸载 Yuan VPS 工具箱本体"
    echo "  将删除：$YUAN_ROOT"
    echo "  将删除：/usr/local/bin/yuan"
    echo "  注意：已部署的节点服务（HY2/Xray等）不会被删除"
    echo
    read -rp "确认卸载？输入 yes 继续: " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "已取消"
        sleep 1
        return
    fi
    rm -rf "$YUAN_ROOT"
    rm -f /usr/local/bin/yuan
    ok "工具箱已卸载"
    echo "再见！"
    exit 0
}

main_menu() {
    load_modules
    local c
    while true; do
        draw_header
        draw_menu
        read -r -p "请输入你的选择: " c < /dev/tty
        case "$c" in
            1|2|3|4) proto_menu "${PROTOS[$((c-1))]}" ;;
            5)  warp_menu ;;
            6)  xlat_menu ;;
            7)  sys_info ;;
            8)  sys_update ;;
            9)  sys_clean ;;
            10) tuning_menu ;;
            11) fw_menu ;;
            12) sec_run ;;
            13) pkgs_menu ;;
            14) show_all_links ;;
            15) net_tcpquality ;;
            16) net_nodequality ;;
            00) update_panel ;;
            88) echo "再见！"; exit 0 ;;
            99) uninstall_panel ;;
            *) warn "无效选项"; sleep 1 ;;
        esac
    done
}
