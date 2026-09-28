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
# 获取公网 IPv4（失败返回空）
get_ipv4() {
    curl -4s --max-time 8 https://ipv4.icanhazip.com 2>/dev/null \
    || curl -4s --max-time 8 https://ip.sb 2>/dev/null \
    || curl -4s --max-time 8 https://ifconfig.me 2>/dev/null | tr -d '[:space:]'
}

# 获取公网 IPv6（失败返回空）
get_ipv6() {
    curl -6s --max-time 8 https://ipv6.icanhazip.com 2>/dev/null \
    || curl -6s --max-time 8 https://ip.sb 2>/dev/null | tr -d '[:space:]'
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

# 端口是否被占用（TCP/UDP）
port_used() {
    ss -tuln 2>/dev/null | grep -qE "[:.]$1([[:space:]]|$)"
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

# ---------------- systemd ----------------
svc_active()  { systemctl is-active --quiet "$1" 2>/dev/null; }
svc_enabled() { systemctl is-enabled --quiet "$1" 2>/dev/null; }

svc_restart() {
    local svc="$1"
    systemctl daemon-reload 2>/dev/null
    systemctl enable "$svc" 2>/dev/null
    systemctl restart "$svc" 2>/dev/null || return 1
    sleep 2
    svc_active "$svc"
}

# ---------------- 杂项 ----------------
# 取 GitHub 仓库最新 release 的 tag（如 v26.3.27），输出 tag，失败返回非零
# 注意：必须用 grep -o 只取 "tag_name":"..." 片段，不能按整行 cut；
# 某些网络下 API 返回的是压缩成单行的 JSON，按整行 cut 会错取成 url 字段
github_latest_tag() {
    local repo="$1" tag
    tag="$(curl -fsSL --max-time 20 "https://api.github.com/repos/${repo}/releases/latest" \
        | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)"
    [[ "$tag" =~ ^v?[0-9] ]] || return 1
    printf '%s' "$tag"
}

# 国家代码（用于链接备注）
geo_cc() {
    curl -s --max-time 8 "http://ip-api.com/line/?fields=countryCode" 2>/dev/null \
        | tr -d '[:space:]' || true
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
