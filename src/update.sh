#!/bin/bash
# ============================================================
# Yuan Panel · 自更新
# git 仓库直接 pull；非 git 安装则重新拉取 tarball
# ============================================================

YUAN_REPO="https://github.com/yuan1228/hy2"

update_panel() {
    bold "—— 检查更新 ——"
    echo
    step "当前版本：$YUAN_VERSION"
    ensure_cmd curl curl

    local remote_ver
    remote_ver="$(curl -fsSL --max-time 15 "$YUAN_REPO/raw/refs/heads/main/version.txt" 2>/dev/null | tr -d '[:space:]')"
    if [[ -z "$remote_ver" ]]; then
        err "无法获取远程版本（网络异常）"
        echo; pause; return 1
    fi
    step "远程版本：$remote_ver"

    if [[ "$remote_ver" == "$YUAN_VERSION" ]]; then
        ok "已是最新版本，无需更新"
        echo; pause; return 0
    fi

    warn "发现新版本 $remote_ver，开始更新…"
    if [[ -d "$YUAN_ROOT/.git" ]]; then
        ensure_cmd git git
        git -C "$YUAN_ROOT" fetch --quiet origin \
            && git -C "$YUAN_ROOT" reset --hard origin/main --quiet \
            || { err "git 更新失败"; echo; pause; return 1; }
    else
        local tmp
        tmp="$(mktemp -d)"
        curl -fsSL --max-time 60 "$YUAN_REPO/archive/refs/heads/main.tar.gz" -o "$tmp/panel.tar.gz" \
            || { rm -rf "$tmp"; err "下载失败"; echo; pause; return 1; }
        tar -xzf "$tmp/panel.tar.gz" -C "$tmp"
        # 排除 bin（保留已下载的核心二进制）后覆盖
        rsync -a --delete --exclude 'bin/' "$tmp/hy2-main/" "$YUAN_ROOT/" 2>/dev/null \
            || cp -rf "$tmp/hy2-main/." "$YUAN_ROOT/"
        rm -rf "$tmp"
    fi

    chmod +x "$YUAN_ROOT/yuan" "$YUAN_ROOT/install.sh"
    ln -sf "$YUAN_ROOT/yuan" /usr/local/bin/yuan
    ok "更新完成！请重新运行 yuan 进入新版本"
    echo
    exit 0
}
