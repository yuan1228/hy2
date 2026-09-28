# 贡献指南

感谢你想为 Yuan Panel 做贡献！

## 加新协议

1. 在 `src/protocols/` 新建 `<id>.sh`
2. 实现 8 个标准函数（把 `<id>` 换成你的协议 id）：
   - `<id>_installed` — 是否已安装（返回 0/1）
   - `<id>_active` — 服务是否运行中
   - `<id>_port` — 输出监听端口
   - `<id>_deploy` — 交互式部署
   - `<id>_link` — 输出分享链接
   - `<id>_restart` — 重启服务
   - `<id>_logs` — 查看日志
   - `<id>_uninstall` — 彻底卸载
   - `<id>_status` — 状态详情
3. 在 `src/menu.sh` 的 `PROTOS` 数组追加 id，并在 `proto_name()` 加显示名
4. 配置统一放 `$YUAN_CONF/<id>/`，链接存 `link.txt`（600 权限）

## 代码规范

- bash，兼容 `bash 4+`
- 所有脚本 `bash -n` 通过；有 shellcheck 时 warning 级别通过
- 含密码的文件一律 600，目录 700（`common.sh` 已设 `umask 077`）
- 密码输入用 `ask_secret`（不回显），普通输入用 `ask_input`
- 端口用 `ask_port`（自动校验 + 占用提醒）
- 网络下载用 `curl -fsSL`，失败必须报错退出，不静默继续
- systemd 服务用 `svc_restart`，启动后验证 `svc_active`

## 提交

- PR 标题简明扼要，说明改了什么、为什么
- 大功能先开 Issue 讨论
