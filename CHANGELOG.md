# 更新日志

## v3.4.0 (2026-10-05)

**纯 IPv6 全面支持**（GitHub 主站/API 无 IPv6 地址，纯 v6 机器原先大面积失败）：

- **修 bug**：`github_latest_tag()` 加 jsDelivr 兜底（有 IPv6），取版本三路：
  GitHub API → github.com 跳转 → jsDelivr data API；IPv4 原逻辑不动
- **修 bug**：Shadowsocks 下载失败时改走 `apt install shadowsocks-rust`
  （Debian 官方源有 IPv6），纯 v6 机器可装上
- **修 bug**：VLESS/Trojan 的 Xray inbound 加 `"listen": "::"`，
  原先默认只监听 IPv4，纯 v6 机器上客户端连不上
- **修 bug**：Hysteria2 端口跳跃加 IPv6 规则（iptables→ip6tables，
  nft 加 ip6 表），纯 v6 下跳跃转发生效；卸载时同步清理 v6 规则
- **修 bug**：防火墙 `fw_allow`/`fw_lockdown` 的 iptables 后端同步加
  ip6tables 放行，纯 v6 下端口能放通
- **修 bug**：Hysteria2 非 systemd（Alpine）路径下载失败时改试
  `apk add hysteria`；Xray 下载失败时给明确手动指引
- **新功能**：`install.sh` / `update.sh` 在 git/GitHub 不可达时，
  改走 jsDelivr 逐文件拉取（有 IPv6），纯 v6 机器可安装/更新工具箱本体
- **修 bug**：Hysteria2 的 systemd 安装路径加 fallback 链：
  官方脚本失败时改直接下载二进制；纯 IPv6 下（GitHub 无 v6）
  给出明确手动安装四步指引，不再只报"检查网络"
- **新功能**：仓库内置 hysteria 二进制（`bin/` 目录，gzip 压缩），
  纯 IPv6 机器经 jsDelivr 自动拉取，无需手动下载、无需中转

## v3.3.0 (2026-10-03)

- **新功能：Hysteria2 端口跳跃**：部署时可选启用，iptables/nftables 把一段
  UDP 端口 DNAT 到主端口，客户端用标准 `mport` 参数定时换端口连接，
  有效对抗 GFW 按端口间歇性封锁。Alpine 自动安装 iptables 并固化开机规则；
  链接使用合规的 `mport=起始-结束` 查询参数（不用逗号写法，标准 URL 库可解析）；
  覆盖安装自动沿用旧跳跃配置，卸载时清理转发规则，状态页显示跳跃信息

## v3.2.1 (2026-10-02)

- **网络调优升级**：`tuning_general`（通用优化）新增 UDP/QUIC 专项——
  默认收发缓冲提到 4MB（原 212KB，Hysteria2 跑 QUIC 时小缓冲是瓶颈）、
  `udp_rmem_min`/`udp_wmem_min`、`udp_mem`、TCP rmem/wmem 三元组、
  `optmem_max`；写入前自动备份旧配置

## v3.2.0 (2026-10-02)

**Alpine 实战修复**（瑞典 Alpine 服务器上 hy2 超时的根因）：

- **修致命 bug**：OpenRC 服务脚本的 `depend() { need net; }` 在 Alpine VPS 上
  因没有 `net` 服务导致 OpenRC 直接拒绝启动，节点超时。改为
  `need localmount` + `use net` 软依赖，任何 Alpine 环境都能起
- **修 bug**：`svc_restart` 在 OpenRC 下改用 stop→start（restart 语义不一致），
  启动失败时显示真实报错，不再 `2>/dev/null` 吃掉
- **修 bug**：`hy2_ensure_bin` 只判文件存在不判能否执行，下载中断的半截
  二进制会被跳过导致起不来；现在校验 `hysteria version` 能跑才算安装成功
- **修 bug**：shadowsocks-rust 在 Alpine 上必须用 `-musl` 构建，glibc 版
  在 musl 系统上无法执行；已按系统自动选择
- **恢复 v3.1.3 的 BBR 修复**：`modprobe tcp_bbr` 被误删已补回，
  Debian/Ubuntu 上 BBR 检测不再误判
- Xray / ssserver 同样加上二进制可执行校验
- README 补充 Alpine 专用一键命令（纯净 Alpine 无 bash，需先 `apk add bash curl`）

## v3.1.3 (2026-09-29)

- **修 BBR 误判**：Debian/Ubuntu 上 BBR 是 `tcp_bbr` 内核模块，默认未加载；
  而 `tcp_available_congestion_control` 只列出已加载的算法，导致脚本在
  6.1 内核上也报错"当前内核不支持 BBR"。检测前先 `modprobe tcp_bbr`，
  仍加载失败才报不支持

## v3.1.2 (2026-09-29)

- **修严重 bug**：VLESS/Trojan 部署后服务永远起不来。`VLESS_SVC` 本来就是
  `yuan-vless.service`（带后缀），而 `_xray.sh` 写 unit 文件时又拼了一次
  `.service`，实际写成了 `/etc/systemd/system/yuan-vless.service.service`，
  `systemctl restart yuan-vless.service` 找不到 unit 而失败，且 journalctl
  毫无日志。改为直接用传入的完整 unit 名；卸载路径同步修正；
  部署时自动清理旧版本遗留的 `.service.service` 错文件

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

## v3.5.0 (2026-10-05)
- 新增【464XLAT 管理】子菜单（主菜单 6）：启动/停止/删除清理/状态+连通性测试
- 464XLAT 架构：DNS64 + NAT64(PLAT) + CLAT(clatd)，纯 IPv6 VPS 访问 IPv4 全方案
- 内置 3 个公共 PLAT 备选：nat64.net、Trex(芬兰x2)、level66(德国)，自动故障切换
- HY2 服务端默认监听 [::]，QUIC 参数优化适配 MTU=1280
- 修复纯 IPv6 环境下载/更新失败：经临时 NAT64 拉取，自动复用本机 464XLAT
- 新增 IPv6 环境检测函数 is_ipv6_only()

## v3.5.2 (2026-10-05)
- nat64_fetch 改为 3 个 DNS64 并行抢跑，最快 10 秒内完成
- 用 curl --dns-servers 直连，不再改写 /etc/resolv.conf，零残留
- 单 DNS 超时 8 秒，总等待上限 45 秒

## v3.5.3 (2026-10-05)
- 修复更新检测 jsDelivr CDN 缓存问题：加时间戳破缓存，确保拿到最新版本号

## v3.5.4 (2026-10-05)
- HY2 配置写入后增加校验：空文件或缺少 listen 字段时直接报错，不再装出坏服务

## v3.5.5 (2026-10-05)
- HY2 配置文件去掉中文注释，避免 YAML 解析器编码问题导致服务启动失败

## v3.5.6 (2026-10-05)
- 主菜单新增 99. 卸载工具箱：一键删除工具箱本体（保留已部署节点）

## v3.5.7 (2026-10-05)
- 修复 HY2 配置 listen 字段 YAML 解析失败：[::] 必须加引号，否则被当成 flow sequence

## v3.5.8 (2026-10-05)
- 四个协议部署时增加国码手动确认：ip-api 的 IPv6 库常不准，回车确认或手动输入

## v3.5.9 (2026-10-05)
- geo_cc 改用 ip.sb 为主数据源（IPv6 地理库更准），ip-api 和 cloudflare trace 做备选

## v3.6.0 (2026-10-05)
- 状态栏新增 WARP 和 464XLAT 状态显示（●运行中/◐已安装未运行/○未安装）
- 464XLAT 菜单加详细说明：是什么、包含 DNS64+NAT64+CLAT、什么时候用
- 主菜单 464XLAT 选项加备注说明
