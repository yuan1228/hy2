#!/bin/bash
# ============================================================
# Yuan Panel · 安装引导
# 一键安装 / 更新面板本体，创建 `yuan` 快捷命令
#
#   bash <(curl -sL https://raw.githubusercontent.com/yuan1228/hy2/refs/heads/main/install.sh)
# ============================================================
set -u

REPO_URL="https://github.com/yuan1228/hy2"
RAW_URL="https://raw.githubusercontent.com/yuan1228/hy2/refs/heads/main"
INSTALL_DIR="/opt/yuan-panel"
BIN_LINK="/usr/local/bin/yuan"

c_info() { echo -e "\e[36m$*\e[0m"; }
c_ok()   { echo -e "\e[32m$*\e[0m"; }
c_warn() { echo -e "\e[33m$*\e[0m"; }
c_err()  { echo -e "\e[31m$*\e[0m"; }

[[ "$EUID" -eq 0 ]] || { c_err "请使用 root 用户运行"; exit 1; }
command -v curl >/dev/null 2>&1 || { c_err "缺少 curl，请先安装"; exit 1; }

c_info "▸ 正在安装 Yuan Panel…"

# 安装 git（用于增量更新）；失败则走 tarball 兜底
if ! command -v git >/dev/null 2>&1; then
    c_info "▸ 安装 git…"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq git
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q git
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q git
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache git
    else
        c_warn "无法自动安装 git，将使用 tarball 方式安装（不支持增量更新）"
    fi
fi

if [[ -d "$INSTALL_DIR/.git" ]] && command -v git >/dev/null 2>&1; then
    c_info "▸ 检测到旧版本，正在更新…"
    git -C "$INSTALL_DIR" fetch --quiet origin \
        && git -C "$INSTALL_DIR" reset --hard origin/main --quiet \
        || { c_err "更新失败，请检查网络"; exit 1; }
elif command -v git >/dev/null 2>&1; then
    c_info "▸ 克隆仓库…"
    rm -rf "$INSTALL_DIR"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" --quiet \
        || { c_err "克隆失败，请检查网络"; exit 1; }
else
    c_info "▸ 下载 tarball…"
    tmp="$(mktemp -d)"
    curl -fsSL --max-time 120 "$REPO_URL/archive/refs/heads/main.tar.gz" -o "$tmp/panel.tar.gz" \
        || { rm -rf "$tmp"; c_err "下载失败"; exit 1; }
    tar -xzf "$tmp/panel.tar.gz" -C "$tmp"
    rm -rf "$INSTALL_DIR"
    mv "$tmp/hy2-main" "$INSTALL_DIR"
    rm -rf "$tmp"
fi

chmod +x "$INSTALL_DIR/yuan" "$INSTALL_DIR/install.sh"
ln -sf "$INSTALL_DIR/yuan" "$BIN_LINK"

c_ok "安装完成！"
echo
c_info "输入 ${BIN_LINK##*/} 即可进入管理面板"
echo

# 直接进入面板
exec "$BIN_LINK"
