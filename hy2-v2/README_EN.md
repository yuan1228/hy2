# Yuan Panel

One-command multi-protocol proxy deployment & management panel for VPS:
Hysteria2, VLESS+REALITY, Trojan, Shadowsocks.

[中文](README.md) · [Protocols](docs/protocols.md) · [Security](docs/security.md) · [FAQ](docs/faq.md)

## Features

- **Multi-protocol**: Hysteria2 / VLESS+REALITY / Trojan / Shadowsocks-2022, can coexist
- **Status dashboard**: see every protocol's state at a glance
- **Secure defaults**: strong random passwords, no-echo password input, 600 config perms, umask 077
- **Firewall**: auto-opens protocol ports; one-click lockdown keeps only SSH + protocol ports
- **Tuning**: BBR (FQ/CAKE), general kernel tweaks
- **Security audit**: one-click check of SSH, permissions, firewall with fix suggestions
- **Self-update**: in-panel update via git

## Quick start

```bash
bash <(curl -sL https://raw.githubusercontent.com/yuan1228/hy2/refs/heads/main/install.sh)
```

After installation, run `yuan` anytime to open the panel.

## Notes

- Root required
- Hysteria2 uses UDP — open UDP in your cloud firewall/security group
- For VLESS REALITY, use small-certificate masquerade targets (default www.cloudflare.com);
  large-cert sites (e.g. www.microsoft.com) break the handshake
- Shadowsocks 2022 needs an up-to-date client

## License

MIT — see [LICENSE](LICENSE).
