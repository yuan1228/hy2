#!/bin/bash
# ============================================================
# Yuan VPS 工具箱 · 自更新
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
    # 纯 IPv6 下 raw.githubusercontent.com 可能不可达；git 安装改用 git 直接读远端 version.txt
    if [[ -z "$remote_ver" && -d "$YUAN_ROOT/.git" ]] && command -v git >/dev/null 2>&1; then
        dim "直连取版本失败，尝试经 git 获取远端版本…"
        git -C "$YUAN_ROOT" fetch --quiet origin 2>/dev/null
        remote_ver="$(git -C "$YUAN_ROOT" show origin/main:version.txt 2>/dev/null | tr -d '[:space:]')"
    fi
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
    local _upd_ok=0
    if [[ -d "$YUAN_ROOT/.git" ]]; then
        ensure_cmd git git
        if git -C "$YUAN_ROOT" fetch --quiet origin 2>/dev/null \
            && git -C "$YUAN_ROOT" reset --hard origin/main --quiet 2>/dev/null; then
            _upd_ok=1
        else
            warn "git 更新失败（GitHub 无 IPv6？），改走 jsDelivr…"
        fi
    fi
    if [[ "$_upd_ok" != "1" ]]; then
        if [[ -d "$YUAN_ROOT/.git" ]]; then
            # git 方式失败，改用 jsDelivr 逐文件更新（保留 bin/ 与配置）
            local _f
            for _f in version.txt yuan install.sh \
                src/common.sh src/menu.sh src/update.sh \
                src/protocols/hysteria2.sh src/protocols/_xray.sh src/protocols/vless.sh \
                src/protocols/trojan.sh src/protocols/shadowsocks.sh \
                src/net/warp.sh src/net/tcpquality.sh src/net/nodequality.sh \
                src/system/firewall.sh src/system/info.sh src/system/maintenance.sh \
                src/system/pkgs.sh src/system/security.sh src/system/tuning.sh; do
                mkdir -p "$YUAN_ROOT/$(dirname "$_f")"
                curl -fsSL --max-time 30 "https://cdn.jsdelivr.net/gh/yuan1228/hy2@main/$_f" \
                    -o "$YUAN_ROOT/$_f" 2>/dev/null || { err "更新失败：$_f"; echo; pause; return 1; }
            done
            _upd_ok=1
        else
            local tmp
            tmp="$(mktemp -d)"
            if curl -fsSL --max-time 60 "$YUAN_REPO/archive/refs/heads/main.tar.gz" -o "$tmp/panel.tar.gz" 2>/dev/null; then
                tar -xzf "$tmp/panel.tar.gz" -C "$tmp"
                rsync -a --delete --exclude 'bin/' "$tmp/hy2-main/" "$YUAN_ROOT/" 2>/dev/null \
                    || cp -rf "$tmp/hy2-main/." "$YUAN_ROOT/"
                _upd_ok=1
            else
                # tarball 也失败（纯 v6），改走 jsDelivr
                warn "tarball 下载失败，改走 jsDelivr…"
                local _f
                for _f in version.txt yuan install.sh \
                    src/common.sh src/menu.sh src/update.sh \
                    src/protocols/hysteria2.sh src/protocols/_xray.sh src/protocols/vless.sh \
                    src/protocols/trojan.sh src/protocols/shadowsocks.sh \
                    src/net/warp.sh src/net/tcpquality.sh src/net/nodequality.sh \
                    src/system/firewall.sh src/system/info.sh src/system/maintenance.sh \
                    src/system/pkgs.sh src/system/security.sh src/system/tuning.sh; do
                    mkdir -p "$YUAN_ROOT/$(dirname "$_f")"
                    curl -fsSL --max-time 30 "https://cdn.jsdelivr.net/gh/yuan1228/hy2@main/$_f" \
                        -o "$YUAN_ROOT/$_f" 2>/dev/null || { rm -rf "$tmp"; err "更新失败：$_f"; echo; pause; return 1; }
                done
                _upd_ok=1
            fi
            rm -rf "$tmp"
        fi
    fi
    [[ "$_upd_ok" == "1" ]] || { err "更新失败"; echo; pause; return 1; }

    chmod +x "$YUAN_ROOT/yuan" "$YUAN_ROOT/install.sh"
    ln -sf "$YUAN_ROOT/yuan" /usr/local/bin/yuan
    ok "更新完成！请重新运行 yuan 进入新版本"
    echo
    exit 0
}
