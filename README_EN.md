# Yuan VPS Toolbox

A curated collection of everyday VPS tools: proxy nodes, WARP, system maintenance,
network testing — all behind one `yuan` command. No website-building bloat.

[中文](README.md) · [Protocols](docs/protocols.md) · [Security](docs/security.md) · [FAQ](docs/faq.md)

## Quick start

```bash
bash <(curl -sL https://raw.githubusercontent.com/yuan1228/hy2/refs/heads/main/install.sh)
```

Then run `yuan` anytime.

## What's inside

- **Proxy nodes**: Hysteria2 / VLESS+REALITY / Trojan / Shadowsocks-2022 + WARP
- **System**: host info, OS update, cleanup, BBR tuning, firewall, security audit
- **Network tests** (auto-check upstream updates before each run): TcpQuality,
  NodeQuality (YABS + IP quality + network quality, sandbox-clean)

## Notes

- Root required; Hysteria2 needs UDP open in your cloud firewall
- Evolved from the hy2 single-protocol script; v1 configs auto-migrate

## License

MIT — see [LICENSE](LICENSE).
