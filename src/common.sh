#!/bin/bash
# ============================================================
# Yuan VPS 工具箱 · 公共库
# 提供颜色输出、系统检测、安全密码、网络工具等基础能力
# 仅被 source 引用，不直接执行
# ============================================================
[[ -n "${_YUAN_COMMON:-}" ]] && return 0
_YUAN_COMMON=1

YUAN_ROOT="${YUAN_ROOT:-/opt/yuan-panel}"
YUAN_CONF="${YUAN_CONF:-/etc/yuan}"
YUAN_BIN_DIR="$YUAN_ROOT/bin"
YUAN_VERSION="$(cat "$YUAN_ROOT/version.txt" 2>/dev/null || echo "2.0.0")"

# 配置文件默认仅所有者可读写
umask 077

# ---------------- 颜色 ----------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RST='\e[0m'; C_BLD='\e[1m'; C_DIM='\e[2m'
    C_RED='\e[31m'; C_GRN='\e[32m'; C_YLW='\e[33m'
    C_BLU='\e[34m'; C_MAG='\e[35m'; C_CYN='\e[36m'
else
    C_RST=''; C_BLD=''; C_DIM=''
    C_RED=''; C_GRN=''; C_YLW=''
    C_BLU=''; C_MAG=''; C_CYN=''
fi

info() { echo -e "${C_CYN}$*${C_RST}"; }
ok()   { echo -e "${C_GRN}$*${C_RST}"; }
warn() { echo -e "${C_YLW}$*${C_RST}"; }
err()  { echo -e "${C_RED}$*${C_RST}" >&2; }
die()  { err "错误：$*"; exit 1; }
step() { echo -e "${C_BLU}▸${C_RST} $*"; }
dim()  { echo -e "${C_DIM}$*${C_RST}"; }
bold() { echo -e "${C_BLD}$*${C_RST}"; }

pause()   { read -r -n 1 -s -p "按任意键继续…" < /dev/tty; echo; }
confirm() { [[ "${QUICK:-0}" == "1" ]] && return 0; local r; read -r -p "${1:-确定吗？} [y/N]: " r < /dev/tty; [[ "$r" =~ ^[Yy]$ ]]; }

# 一键模式：QUICK=1 时 ask_input/ask_secret 直接取默认值，不交互

# ---------------- 基础检查 ----------------
need_root() { [[ "$EUID" -eq 0 ]] || die "请使用 root 用户运行"; }
need_cmd()  { command -v "$1" >/dev/null 2>&1 || die "缺少依赖命令：$1"; }

# ---------------- 系统信息 ----------------
# 输出: id|version|virt|arch  (缓存到全局变量)
_sysinfo_done=0
sysinfo() {
    (( _sysinfo_done )) && return 0
    _sysinfo_done=1
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        SYS_OS="$ID"; SYS_VER="$VERSION_ID"
    else
        SYS_OS="unknown"; SYS_VER=""
    fi
    SYS_VIRT="$(systemd-detect-virt 2>/dev/null || echo none)"
    case "$(uname -m)" in
        x86_64)  SYS_ARCH="amd64" ;;
        aarch64) SYS_ARCH="arm64" ;;
        *)       SYS_ARCH="$(uname -m)" ;;
    esac
}

# 用发行版包管理器安装缺失的包
pkg_install() {
    sysinfo
    case "$SYS_OS" in
        debian|ubuntu|kali)
            apt-get update -qq && apt-get install -y -qq "$@" ;;
        centos|rhel|almalinux|rocky|fedora)
            (dnf install -y -q "$@" || yum install -y -q "$@") ;;
        alpine)
            apk add --no-cache "$@" ;;
        *)
            die "不支持的发行版：$SYS_OS，请手动安装：$*" ;;
    esac
}

ensure_cmd() {
    command -v "$1" >/dev/null 2>&1 && return 0
    warn "正在安装缺失依赖：$1 …"
    pkg_install "$2" || die "依赖 $1 安装失败"
}

# ---------------- 安全 ----------------
# 生成高强度随机密码：默认 24 字节 base64（约 32 字符）
gen_pass() {
    local bytes="${1:-24}"
    need_cmd openssl
    openssl rand -base64 "$bytes" | tr -d '/+=' | cut -c1-32
}

# 生成 hex 密码（仅 [0-9a-f]，兼容性最好）
gen_hex() {
    local bytes="${1:-16}"
    need_cmd openssl
    openssl rand -hex "$bytes"
}

# 交互读取密码（不回显）；留空则使用默认值
# 用法: ask_secret "提示" "默认值" 变量名
ask_secret() {
    local prompt="$1" def="$2" var="$3" _in
    if [[ "${QUICK:-0}" == "1" ]]; then
        printf -v "$var" '%s' "$def"
        return 0
    fi
    if [[ -n "$def" ]]; then
        read -r -s -p "$prompt（留空保留旧值，不回显）: " _in < /dev/tty
    else
        read -r -s -p "$prompt（不回显）: " _in < /dev/tty
    fi
    echo
    printf -v "$var" '%s' "${_in:-$def}"
}

# 普通输入（带默认值）
# 用法: ask_input "提示" "默认值" 变量名
ask_input() {
    local prompt="$1" def="$2" var="$3" _in
    if [[ "${QUICK:-0}" == "1" ]]; then
        printf -v "$var" '%s' "$def"
        return 0
    fi
    if [[ -n "$def" ]]; then
        read -r -p "$prompt（默认 $def）: " _in < /dev/tty
    else
        read -r -p "$prompt: " _in < /dev/tty
    fi
    printf -v "$var" '%s' "${_in:-$def}"
}

# URL 编解码（分享链接用）
urlencode() {
    local s="$1" out="" c hex i
    for (( i=0; i<${#s}; i++ )); do
        c="${s:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) out+="$c" ;;
            *) printf -v hex '%%%02X' "'$c"; out+="$hex" ;;
        esac
    done
    printf '%s' "$out"
}
urldecode() {
    printf '%b' "$(printf '%s' "$1" | sed -E 's/%([0-9A-Fa-f]{2})/\\x\1/g')"
}

# base64url（SS 链接用）
b64url() { printf '%s' "$1" | base64 -w0 | tr '+/' '-_' | tr -d '='; }

# ---------------- 网络 ----------------
# 检查是否有真实 IPv4（排除 clat 翻译接口）
has_real_ipv4() {
    # 排除 CLAT 接口：clatd 固定用 192.0.0.1/29（RFC 7335），按地址段判断比接口名可靠
    ip -4 addr show scope global 2>/dev/null | grep "inet " | grep -vq "192\.0\.0\."
}

# 获取公网 IPv4（失败返回空）
# 注意：464XLAT 运行时 curl -4 也能通（经 NAT64），但那是网关 IP 不能用
get_ipv4() {
    # 没有真实 IPv4 地址时直接返回空，避免拿到 NAT64 网关 IP
    has_real_ipv4 || return 1
    local iface_opt=""
    # 双栈+464XLAT 同时开时，默认 v4 路由可能走 clat，需绑定真实 v4 地址
    if ip -4 route show default 2>/dev/null | grep -q "dev clat"; then
        local real_ip
        real_ip="$(ip -4 addr show scope global 2>/dev/null | grep "inet " | grep -v "192\.0\.0\." | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -1)"
        [[ -n "$real_ip" ]] && iface_opt="--interface $real_ip"
    fi
    { curl $iface_opt -4s --max-time 8 https://ipv4.icanhazip.com 2>/dev/null \
    || curl $iface_opt -4s --max-time 8 https://ip.sb 2>/dev/null \
    || curl $iface_opt -4s --max-time 8 https://ifconfig.me 2>/dev/null; } | tr -d '[:space:]'
}

# 获取公网 IPv6（失败返回空）
get_ipv6() {
    { curl -6s --max-time 8 https://ipv6.icanhazip.com 2>/dev/null \
    || curl -6s --max-time 8 https://ip.sb 2>/dev/null; } | tr -d '[:space:]'
}

# 优先 v4，没有 v4 则用 [v6]
get_pubip() {
    local v4 v6
    v4="$(get_ipv4)"
    if [[ -n "$v4" ]]; then printf '%s' "$v4"; return 0; fi
    v6="$(get_ipv6)"
    if [[ -n "$v6" ]]; then printf '[%s]' "$v6"; return 0; fi
    return 1
}

# 列出当前监听端口（ss 不可用时回退到 netstat，供展示用）
show_listening() {
    if command -v ss >/dev/null 2>&1; then
        ss -tuln 2>/dev/null | awk 'NR>1 {print "  " $1, $5}' | sort -u
    else
        netstat -tuln 2>/dev/null | awk 'NR>1 {print "  " $1, $4}' | sort -u
    fi
}

# 端口是否被占用（TCP/UDP）；ss 不可用时（如 Alpine 精简版）回退到 netstat
port_used() {
    if command -v ss >/dev/null 2>&1; then
        ss -tuln 2>/dev/null | grep -qE "[:.]$1([[:space:]]|$)"
    else
        netstat -tuln 2>/dev/null | grep -qE "[:.]$1([[:space:]]|$)"
    fi
}

# 校验端口合法性
valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

# 交互式索取端口（含校验与占用提醒）
# 用法: ask_port "提示" "默认值" 变量名
ask_port() {
    local prompt="$1" def="$2" var="$3" val yn
    while true; do
        ask_input "$prompt" "$def" val
        valid_port "$val" || { err "端口不合法：$val（需 1-65535）"; continue; }
        if port_used "$val"; then
            warn "端口 $val 疑似已被占用。"
            confirm "仍要继续吗？" || continue
        fi
        break
    done
    printf -v "$var" '%s' "$val"
}

# ---------------- init 系统抽象（systemd / OpenRC） ----------------
# SYS_INIT: systemd | openrc | unknown（首次调用 detect_init 时确定并缓存）
SYS_INIT=""

detect_init() {
    [[ -n "$SYS_INIT" ]] && return 0
    if [[ -d /run/systemd/system ]]; then
        SYS_INIT="systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        SYS_INIT="openrc"
    else
        SYS_INIT="unknown"
    fi
}

# 服务名标准化：去掉 .service 后缀（OpenRC 服务名不带后缀）
svc_name() { printf '%s' "${1%.service}"; }

svc_active() {
    detect_init
    local name
    name="$(svc_name "$1")"
    case "$SYS_INIT" in
        systemd) systemctl is-active --quiet "$1" 2>/dev/null ;;
        openrc)  rc-service "$name" status >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

svc_enabled() {
    detect_init
    local name
    name="$(svc_name "$1")"
    case "$SYS_INIT" in
        systemd) systemctl is-enabled --quiet "$1" 2>/dev/null ;;
        openrc)  rc-update show default 2>/dev/null | grep -qE "^[[:space:]]*${name}[[:space:]]" ;;
        *) return 1 ;;
    esac
}

svc_restart() {
    detect_init
    local svc="$1" name
    name="$(svc_name "$svc")"
    case "$SYS_INIT" in
        systemd)
            systemctl daemon-reload 2>/dev/null
            systemctl enable "$svc" 2>/dev/null
            systemctl restart "$svc" 2>/dev/null || return 1
            ;;
        openrc)
            rc-update add "$name" default 2>/dev/null
            # 先停后起比 restart 更稳：restart 在服务从未启动过时行为不一致；
            # 启动失败时保留报错输出，方便排查（不再 2>/dev/null 吃掉）
            rc-service "$name" stop >/dev/null 2>&1
            if ! rc-service "$name" start; then
                err "服务 $name 启动失败"
                return 1
            fi
            ;;
        *) return 1 ;;
    esac
    sleep 2
    svc_active "$svc"
}

svc_stop() {
    detect_init
    local name
    name="$(svc_name "$1")"
    case "$SYS_INIT" in
        systemd) systemctl stop "$1" 2>/dev/null ;;
        openrc)  rc-service "$name" stop 2>/dev/null ;;
    esac
}

# 安装服务：根据 init 系统写入 systemd unit 或 OpenRC init 脚本并设为开机自启
# 用法: svc_install <服务名.service> <描述> <可执行文件> <启动参数> [日志文件]
# 示例: svc_install "yuan-ss.service" "Yuan Shadowsocks" "/usr/local/bin/ssserver" "-c /etc/yuan/ss/config.json"
svc_install() {
    detect_init
    local svc="$1" desc="$2" cmd="$3" args="${4:-}" logfile="$5" name
    name="$(svc_name "$svc")"
    [[ -n "$logfile" ]] || logfile="/var/log/${name}.log"
    case "$SYS_INIT" in
        systemd)
            cat > "/etc/systemd/system/${svc}" <<EOF
[Unit]
Description=$desc
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=$cmd $args
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
            ;;
        openrc)
            cat > "/etc/init.d/${name}" <<EOF
#!/sbin/openrc-run
description="$desc"
command="$cmd"
command_args="$args"
command_background=true
pidfile="/run/${name}.pid"
output_log="$logfile"
error_log="$logfile"

depend() {
    # 注意：不要用 "need net" —— Alpine VPS 上通常没有配置 net.* 服务，
    # 硬依赖会导致 OpenRC 直接拒绝启动。用 use/after 做软依赖最稳。
    need localmount
    use net dns
    after firewall
}
EOF
            chmod +x "/etc/init.d/${name}"
            ;;
        *) err "不支持的 init 系统，无法安装服务"; return 1 ;;
    esac
}

# 卸载服务：停止、取消自启、删除服务定义
# 用法: svc_uninstall <服务名.service>
svc_uninstall() {
    detect_init
    local svc="$1" name
    name="$(svc_name "$svc")"
    case "$SYS_INIT" in
        systemd)
            systemctl stop "$svc" 2>/dev/null
            systemctl disable "$svc" 2>/dev/null
            rm -f "/etc/systemd/system/${svc}"
            rm -rf "/etc/systemd/system/${svc}.d"
            systemctl daemon-reload 2>/dev/null
            ;;
        openrc)
            rc-service "$name" stop 2>/dev/null
            rc-update del "$name" default 2>/dev/null
            rm -f "/etc/init.d/${name}"
            ;;
    esac
}

# 查看服务日志（最近 N 行）：svc_logs <服务名.service> [行数]
svc_logs() {
    detect_init
    local svc="$1" lines="${2:-60}" name logfile
    name="$(svc_name "$svc")"
    case "$SYS_INIT" in
        systemd) journalctl -u "$svc" -n "$lines" --no-pager 2>/dev/null ;;
        openrc)
            logfile="/var/log/${name}.log"
            if [[ -f "$logfile" ]]; then tail -n "$lines" "$logfile"
            else warn "暂无日志文件：$logfile"; fi
            ;;
    esac
}

# 实时跟踪服务日志：svc_logs_follow <服务名.service>
svc_logs_follow() {
    detect_init
    local svc="$1" name logfile
    name="$(svc_name "$svc")"
    case "$SYS_INIT" in
        systemd) journalctl -u "$svc" -f --output cat 2>/dev/null ;;
        openrc)
            logfile="/var/log/${name}.log"
            if [[ -f "$logfile" ]]; then tail -f "$logfile"
            else warn "暂无日志文件：$logfile"; fi
            ;;
    esac
}

# ---------------- 杂项 ----------------
# 临时 DNS64 下载：纯 IPv6 下经 NAT64 拉 GitHub，完事恢复 resolv.conf，不留残留
# 用法：nat64_fetch <url> <输出文件>；成功返回 0
nat64_fetch() {
    local url="$1" out="$2"
    local dns64_list="2a00:1098:2b::1 2001:67c:2b0::4 2001:67c:2960::64"
    local rc=1 resolv_bak
    resolv_bak="$(mktemp)"
    # 备份 resolv.conf（Debian curl 不支持 --dns-servers，只能临时改写）
    cp /etc/resolv.conf "$resolv_bak" 2>/dev/null
    # 逐个尝试 DNS64，串行避免竞态
    for dns64 in $dns64_list; do
        printf 'nameserver %s\n' "$dns64" > /etc/resolv.conf
        if curl -fsSL --connect-timeout 8 --max-time 30 "$url" -o "$out" 2>/dev/null; then
            rc=0
            break
        fi
    done
    # 恢复 resolv.conf
    cp "$resolv_bak" /etc/resolv.conf 2>/dev/null
    rm -f "$resolv_bak"
    return $rc
}

# 取 GitHub 仓库最新 release 的 tag（如 v26.3.27），输出 tag，失败返回非零
# 注意：必须用 grep -o 只取 "tag_name":"..." 片段，不能按整行 cut；
# 某些网络下 API 返回的是压缩成单行的 JSON，按整行 cut 会错取成 url 字段
github_latest_tag() {
    local repo="$1" tag
    tag="$(curl -fsSL --max-time 20 "https://api.github.com/repos/${repo}/releases/latest" \
        | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)"
    if [[ "$tag" =~ ^v?[0-9] ]]; then
        printf '%s' "$tag"
        return 0
    fi
    # API 不可达时（如纯 IPv6 小鸡连不上 api.github.com），改从 releases/latest
    # 的跳转地址解析版本；github.com 主站一般可达，不影响原有 IPv4 逻辑
    tag="$(curl -fsSL -o /dev/null -w '%{url_effective}' --max-time 20 \
        "https://github.com/${repo}/releases/latest" 2>/dev/null \
        | sed -n 's|.*/releases/tag/||p' | cut -d'?' -f1 | cut -d'#' -f1 | head -1)"
    if [[ "$tag" =~ ^v?[0-9] ]]; then
        printf '%s' "$tag"
        return 0
    fi
    # jsDelivr 兜底：有 IPv6，GitHub 主站/API 均无 IPv6 时用；
    # 返回的 version 无 v 前缀（如 1.25.0），补上以匹配 GitHub tag 格式
    tag="$(curl -fsSL --max-time 20 "https://data.jsdelivr.com/v1/packages/gh/${repo}" 2>/dev/null \
        | grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)"
    if [[ "$tag" =~ ^[0-9] ]]; then
        tag="v$tag"
    fi
    [[ "$tag" =~ ^v?[0-9] ]] || return 1
    printf '%s' "$tag"
}

# 国家代码（用于链接备注）
geo_cc() {
    local cc=""
    local curl_v=""
    # 纯 IPv6 机器强制走 IPv6 查，避免经 NAT64 拿到网关所在国的国码
    if ! has_real_ipv4; then
        curl_v="-6"
    fi
    # 首选 ip.sb（权威，IPv6 库准）
    cc="$(curl $curl_v -s --max-time 8 "https://api.ip.sb/geoip" 2>/dev/null \
        | grep -oE '"country_code"[[:space:]]*:[[:space:]]*"[A-Z]+"' | head -1 | cut -d'"' -f4 | tr -d '[:space:]')"
    # 备选 ip-api.com
    if [[ -z "$cc" ]]; then
        cc="$(curl $curl_v -s --max-time 8 "http://ip-api.com/line/?fields=countryCode" 2>/dev/null \
            | tr -d '[:space:]')"
    fi
    # 备选 cloudflare trace
    if [[ -z "$cc" ]]; then
        cc="$(curl $curl_v -s --max-time 8 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null \
            | grep "^loc=" | cut -d= -f2 | tr -d '[:space:]')"
    fi
    printf '%s' "$cc" || true
}

ensure_dir() { mkdir -p "$1" && chmod 700 "$1"; }

# ---------------- 第三方网络测试脚本 ----------------
# 每次运行前检查上游更新：有更新则先更新再运行；拉取失败则用本地缓存
# 用法: net_tool_run "工具名" "下载URL" "缓存文件名" [传给脚本的参数...]
# 成功时输出可用脚本路径并返回 0
net_tool_run() {
    local name="$1" url="$2" cachefile="$3"
    shift 3
    local cachedir="$YUAN_ROOT/cache" tmp
    local cache="$cachedir/$cachefile"
    mkdir -p "$cachedir"
    chmod 700 "$cachedir" 2>/dev/null
    tmp="$(mktemp)"

    step "检查 $name 上游更新…"
    if curl -fsSL --max-time 120 "$url" -o "$tmp"; then
        if [[ -f "$cache" ]] && cmp -s "$tmp" "$cache"; then
            ok "$name 已是最新版"
            rm -f "$tmp"
        else
            [[ -f "$cache" ]] && warn "$name 发现新版本，正在更新…"
            mv "$tmp" "$cache"
            chmod 600 "$cache"
            ok "$name 已更新到最新版"
        fi
    else
        rm -f "$tmp"
        if [[ -f "$cache" ]]; then
            warn "上游拉取失败，使用本地缓存版本运行"
        else
            err "$name 下载失败，且无本地缓存"
            return 1
        fi
    fi

    echo
    info "正在运行 $name…"
    echo
    bash "$cache" "$@"
}

# 从节点链接中提取端口（支持 IPv6 中括号地址）
# 用法：url_port "hysteria2://pass@[2001:db8::1]:48978?..." → 48978
url_port() {
    local url="$1" host_port
    # 取 @ 之后、?/# 之前的部分
    host_port="$(printf '%s' "$url" | sed -n 's|.*@\([^?#]*\).*|\1|p')"
    # 如果是 [ipv6]:port 格式
    if [[ "$host_port" =~ ^\[.*\]:([0-9]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    # 普通 host:port 格式
    elif [[ "$host_port" =~ :([0-9]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    fi
}

# 监听地址：IPv6 可用时用 [::]（双栈），内核禁用 IPv6 时回退 0.0.0.0
# 用法：listen_addr → "[::]" 或 "0.0.0.0"
listen_addr() {
    if [[ -d /proc/net/if_inet6 ]]; then
        printf '[::]'
    else
        printf '0.0.0.0'
    fi
}

# Xray 的 listen 字段格式（不带中括号）
# 用法：xray_listen → "::" 或 "0.0.0.0"
xray_listen() {
    if [[ -d /proc/net/if_inet6 ]]; then
        printf '::'
    else
        printf '0.0.0.0'
    fi
}
