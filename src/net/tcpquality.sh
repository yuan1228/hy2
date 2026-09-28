#!/bin/bash
# ============================================================
# Yuan VPS 工具箱 · 网络测试：TcpQuality
# TCP 质量检测（默认测全国三网），上游：ibsgss/TcpQuality
# 每次运行前自动检查更新
# ============================================================

TCPQUALITY_URL="https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh"

net_tcpquality() {
    clear
    bold "—— TcpQuality · TCP 质量检测 ——"
    echo
    dim "默认检测全国三网运营商节点的 TCP 质量（含回程/丢包/抖动）"
    dim "报告示例：https://tcpquality.ibsgss.uk"
    echo
    echo "  1. 默认检测（三网）"
    echo "  2. 仅 IPv4 三网"
    echo "  3. 仅 IPv6 三网"
    echo "  4. 追加单线程测速"
    echo "  0. 返回"
    echo
    local c args=()
    read -r -p "请选择 [0-4]: " c < /dev/tty
    case "$c" in
        1) args=() ;;
        2) args=(-v4) ;;
        3) args=(-v6) ;;
        4) args=(--speedtest) ;;
        0) return 0 ;;
        *) warn "无效选项"; sleep 1; return 0 ;;
    esac
    net_tool_run "TcpQuality" "$TCPQUALITY_URL" "tcpquality.sh" "${args[@]}" \
        || { echo; pause; return 1; }
    echo
    pause
}
