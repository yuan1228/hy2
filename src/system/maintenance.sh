#!/bin/bash
# ============================================================
# Yuan Toolbox · 系统工具：系统更新 / 系统清理
# ============================================================

sys_update() {
    sysinfo
    bold "—— 系统更新 ——"
    echo
    confirm "将更新软件包索引并升级全部软件包，继续吗？" || return 0
    echo
    case "$SYS_OS" in
        debian|ubuntu|kali)
            step "apt update…"
            apt-get update || { err "update 失败"; echo; pause; return 1; }
            step "apt upgrade…"
            DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
                || { err "upgrade 失败"; echo; pause; return 1; }
            ;;
        centos|rhel|almalinux|rocky|fedora)
            step "升级软件包…"
            (dnf upgrade -y || yum update -y) \
                || { err "升级失败"; echo; pause; return 1; }
            ;;
        alpine)
            step "apk upgrade…"
            apk update && apk upgrade \
                || { err "升级失败"; echo; pause; return 1; }
            ;;
        *)
            err "不支持的发行版：$SYS_OS"; echo; pause; return 1 ;;
    esac
    echo
    ok "系统更新完成"
    if [[ -f /var/run/reboot-required ]]; then
        warn "内核已更新，建议重启生效：reboot"
    fi
    echo
    pause
}

sys_clean() {
    sysinfo
    bold "—— 系统清理 ——"
    echo
    local before after
    before="$(df -h / | awk 'NR==2{print $4}')"
    echo "清理前 / 可用空间：$before"
    echo
    confirm "将清理包缓存、无用依赖、旧日志与临时文件，继续吗？" || return 0
    echo

    case "$SYS_OS" in
        debian|ubuntu|kali)
            step "清理 apt 缓存…"
            apt-get clean -qq
            apt-get autoremove -y -qq 2>/dev/null
            ;;
        centos|rhel|almalinux|rocky|fedora)
            step "清理包缓存…"
            (dnf clean all -q || yum clean all -q) 2>/dev/null
            ;;
        alpine)
            step "清理 apk 缓存…"
            rm -rf /var/cache/apk/* 2>/dev/null
            ;;
    esac

    step "清理 journal 日志（保留最近 7 天）…"
    journalctl --vacuum-time=7d >/dev/null 2>&1

    step "清理临时文件…"
    rm -rf /tmp/* /var/tmp/* 2>/dev/null

    after="$(df -h / | awk 'NR==2{print $4}')"
    echo
    ok "清理完成：/ 可用空间 $before → $after"
    echo
    pause
}
