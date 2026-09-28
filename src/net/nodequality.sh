#!/bin/bash
# ============================================================
# Yuan VPS 工具箱 · 网络测试：NodeQuality
# VPS 综合体检（YABS + IP 质量 + 网络质量），沙箱无痕运行
# 上游：LloydAsp/NodeQuality，每次运行前自动检查更新
# ============================================================

NODEQUALITY_URL="https://run.NodeQuality.com"

net_nodequality() {
    clear
    bold "—— NodeQuality · VPS 综合体检 ——"
    echo
    dim "包含：YABS 性能测试 + IP 质量（含流媒体解锁）+ 网络质量（回程路由）"
    dim "沙箱运行，测完自动清理，不留痕迹；结果自动排版并上传"
    echo
    if ! curl -s --max-time 10 -o /dev/null https://github.com 2>/dev/null; then
        warn "检测到 GitHub 可能不可达，NodeQuality 需从 GitHub 下载 BenchOS"
        warn "可先用 WARP（菜单 5）给机器加出口后再测"
        echo
        confirm "仍要继续吗？" || return 0
        echo
    fi
    net_tool_run "NodeQuality" "$NODEQUALITY_URL" "nodequality.sh" \
        || { echo; pause; return 1; }
    echo
    pause
}
