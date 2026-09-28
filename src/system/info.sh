#!/bin/bash
# ============================================================
# Yuan Toolbox · 系统工具：本机信息
# ============================================================

sys_info() {
    sysinfo
    clear
    bold "—— 本机信息 ——"
    echo

    local cpu model cores mem_total mem_used disk_total disk_used up load ip4 ip6 geo

    model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)"
    [[ -z "$model" ]] && model="$(uname -m) (未知型号)"
    cores="$(nproc 2>/dev/null || grep -c processor /proc/cpuinfo)"
    mem_total="$(free -h 2>/dev/null | awk '/^Mem:/{print $2}')"
    mem_used="$(free -h 2>/dev/null | awk '/^Mem:/{print $3}')"
    disk_total="$(df -h / 2>/dev/null | awk 'NR==2{print $2}')"
    disk_used="$(df -h / 2>/dev/null | awk 'NR==2{print $3}')"
    up="$(uptime -p 2>/dev/null | sed 's/up //')"
    load="$(uptime 2>/dev/null | grep -oE 'load average[^,]*,[^,]*,[^,]*' | cut -d: -f2 | xargs)"

    echo -e "${C_BLD}硬件${C_RST}"
    echo "  CPU      : $model × $cores"
    echo "  内存     : $mem_used / $mem_total"
    echo "  硬盘     : $disk_used / $disk_total (/ 分区)"
    echo
    echo -e "${C_BLD}系统${C_RST}"
    echo "  发行版   : $SYS_OS $SYS_VER"
    echo "  内核     : $(uname -r)"
    echo "  架构     : $SYS_ARCH"
    echo "  虚拟化   : $SYS_VIRT"
    echo "  运行时间 : $up"
    echo "  负载     : $load"
    echo
    echo -e "${C_BLD}网络${C_RST}"
    step "正在查询 IP 信息…"
    ip4="$(get_ipv4)"; ip6="$(get_ipv6)"
    geo="$(curl -s --max-time 10 "http://ip-api.com/json/?fields=country,city,isp,org" 2>/dev/null)"
    echo "  IPv4     : ${ip4:-无}"
    echo "  IPv6     : ${ip6:-无}"
    if [[ -n "$geo" ]]; then
        echo "  归属     : $(printf '%s' "$geo" | grep -oE '"country":"[^"]*"' | cut -d'"' -f4) $(printf '%s' "$geo" | grep -oE '"city":"[^"]*"' | cut -d'"' -f4)"
        echo "  运营商   : $(printf '%s' "$geo" | grep -oE '"isp":"[^"]*"' | cut -d'"' -f4)"
    fi
    echo
    pause
}
