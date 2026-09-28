# 更新日志

## v3.1.1 (2026-09-29)

- **修严重 bug**：GitHub API 版本号解析在某些网络下会拿到错误值。某些网络
  （代理/CDN）返回的 release JSON 是压缩成单行的，旧写法按整行 `cut` 会把
  `url` 字段（`https://api.github.com/.../releases/302486999`）当成版本号，
  导致 Xray 下载 404、部署在 [1/5] 直接失败。改为 `grep -o` 只取
  `"tag_name":"..."` 片段（兼容单行/多行 JSON），并加版本号格式校验，
  解析失败时直接报错而不是去下载垃圾 URL。影响 `_xray.sh` 与 `shadowsocks.sh`；
  顺带消除了 `curl: (23)` 的虚惊报错（`grep -m1` 提前关管道导致的）

## v3.1.0 (2026-09-28)

- **网络测试换装**：TcpQuality（TCP 三网质量检测）+ NodeQuality（综合体检：
  YABS + IP 质量 + 网络质量，沙箱无痕运行），替代原 bench.sh / 流媒体解锁 /
  回程路由（功能被两者覆盖）
- **自动更新检查**：两个测试脚本每次运行前自动比对上游，有更新则先更新再运行；
  上游拉取失败时自动降级用本地缓存
- **节点部署双模式**：一键部署（全默认）/ 自定义部署（逐项设置）
- **修 bug**：`ask_input`/`ask_secret` 内部 `local val` 遮蔽了调用者的同名变量，
  导致 `ask_port` 永远拿不到端口值（一键/自定义部署都会卡死）；内部变量改名 `_in`

## v3.0.0 (2026-09-28)

定位调整：从"多协议节点面板"升级为 **VPS 常用工具箱**（参考 eooce/ssh_tool 的思路，
但砍掉建站/Docker 应用等花哨内容，只留 VPS 玩家天天用的东西）。

新增：

- **WARP 管理**：基于 fscarmen/warp-sh，IPv4/IPv6/双栈一键安装、开关、卸载
- **本机信息**：CPU/内存/硬盘/系统/虚拟化/IP/归属地/运营商一屏展示
- **系统更新**：apt/dnf/yum/apk 一键全量升级
- **系统清理**：包缓存、无用依赖、旧日志、临时文件，清理前后对比空间
- **常用组件安装**：curl/wget/git/vim/htop/tmux/mtr/fail2ban 等，可多选
- **VPS 综合测试**：bench.sh（三网测速）/ speedtest-cli
- **流媒体解锁检测**：Netflix / Disney+ / ChatGPT 等
- **回程路由测试**：三网回程一键测试、mtr 手动追踪

菜单改为 eooce 式双栏布局：`00` 检查更新、`88` 退出。

## v2.0.0 (2026-09-28)

完全重构：

- **多协议**：新增 VLESS+REALITY（Xray）、Trojan（Xray）、Shadowsocks 2022（rust）
- **新架构**：模块化结构（`src/protocols/`、`src/system/`）
- **状态仪表盘**：主菜单顶部实时显示各协议运行状态
- **安全增强**：高强度随机密码、密码不回显、umask 077、600 权限、
  防火墙模块、安全检查
- **安装方式**：`install.sh` 改为引导器，面板本体到 `/opt/yuan-panel`，
  git 增量更新；`yuan` 命令进入
- **文档与工程规范**：MIT、Issue 模板、shellcheck CI

## v1.x

- 单文件 `install.sh`，仅支持 Hysteria2
