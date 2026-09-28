#!/bin/bash
# ============================================================
# Yuan VPS 工具箱 · 系统模块：安全检查
# 只读审计 + 分级建议，不自动修改高危配置
# ============================================================

sec_run() {
clear
bold "—— 安全检查报告 ——"
echo
local score=0 total=0
local line

check() { # $1=标题 $2=检测命令(返回0为通过) $3=建议
total=$((total+1))
if eval "$2" >/dev/null 2>&1; then
score=$((score+1))
echo -e " ${C_GRN}✓${C_RST} $1"
else
echo -e " ${C_RED}✗${C_RST} $1"
[[ -n "$3" ]] && echo -e " ${C_DIM}建议：$3${C_RST}"
fi
}

echo ""
check "SSH 禁止 root 密码登录" \
"! grep -Eq '^#?PermitRootLogin[[:space:]]+(yes|prohibit-password)' /etc/ssh/sshd_config" \
"sshd_config 中设置 PermitRootLogin prohibit-password 或 no"
check "SSH 禁止密码认证" \
"grep -Eq '^PasswordAuthentication[[:space:]]+no' /etc/ssh/sshd_config" \
"确认密钥登录可用后，设置 PasswordAuthentication no"
echo
echo ""
check "协议配置目录权限为 700" \
"test ! -d $YUAN_CONF || test \$(stat -c %a $YUAN_CONF) = 700" \
"执行 chmod 700 $YUAN_CONF"
check "分享链接文件权限为 600" \
"! find $YUAN_CONF -name 'link.txt'! -perm 600 2>/dev/null | grep -q." \
"含密码的链接文件应 chmod 600"
echo
echo ""
check "防火墙后端可用" \
"test \$(fw_backend) != none" \
"安装 nftables 或 iptables，并在面板中一键收紧"
check "BBR 拥塞算法已启用" \
"test \$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) = bbr" \
"面板「系统网络调优」中启用 BBR"
echo
echo ""
check "fail2ban 已安装运行" \
"systemctl is-active --quiet fail2ban" \
"apt install fail2ban 可防 SSH 爆破"
check "非常驻：无可疑的定时任务" \
"! crontab -l 2>/dev/null | grep -qE 'curl|wget.*sh\|'" \
"检查 crontab -l，确认无陌生下载执行项"

echo
echo "———————————————"
if (( score == total)); then
ok "全部通过：$score/$total"
elif (( score * 2 >= total)); then
warn "基本合格：$score/$total，请处理上面的 ✗ 项"
else
err "风险较高：$score/$total，强烈建议逐项整改"
fi
echo
dim "当前监听端口（人工复核）："
ss -tuln 2>/dev/null | awk 'NR>1 {print " " $1, $5}' | sort -u
echo
pause
}
