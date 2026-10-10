---
name: kitty
description: Running kitty from this home-manager setup with per-instance overrides — a window whose clicked links open in another browser profile (e.g. the private LibreWolf inside with-vpn), and a window that skips the saved session. Load when the user wants links from a terminal (opencode, Claude Code, any TUI) to open somewhere other than the default browser, a kitty without the restored tabs, or asks how kitty's session or URL opening is set up.
---

# kitty overrides

kitty's config is `home-manager/home-files/kitty.conf`, linked to `~/.config/kitty/kitty.conf` by `kitty.nix`. Any setting in it can be overridden for one kitty instance with `kitty -o name=value`. Nothing below needs a change to the repo.

## Links into the private LibreWolf, in a fresh window

Start the private browser behind the VPN as usual:

```
with-vpn switzerland -- librewolf --class "UNIQUEPRI" -P private
```

Then open the terminal for the work whose links should land there:

```
kitty -o startup_session=none -o open_url_with='librewolf -P private --new-tab'
```

- **`open_url_with`:** the command kitty runs for a clicked link, with the URL appended.
  - `librewolf -P private --new-tab <url>` hands the URL to the LibreWolf already running with the `private` profile: a new tab in the VPN window.
  - The user checked the hand-off works across vopono's namespace on 2026-10-10, with `librewolf -P private --new-tab https://ifconfig.me`.
  - Other kitty windows keep the default, which uses `xdg-open` and so the normal browser.
- **`startup_session=none`:** skips the saved tabs in `~/.config/kitty/session.conf`, which `kitty.conf` loads through `startup_session`. `none` is that option's default, so the window opens with one plain tab.
- Another profile or browser is just another value: `-o open_url_with='firefox -P work --new-tab'`.

### Why kitty, not opencode

- Links in a TUI are opened by the terminal.
- When the app has grabbed the mouse, as opencode does, **Shift+click** the link so kitty handles it.
- Under `sandbox-run`, opencode couldn't start a browser anyway. The bubblewrap layer hides the session D-Bus and gives it a private `/tmp`, where the X display socket lives. kitty runs outside the sandbox.

### Watch out

- **Leaving the VPN:** if the private LibreWolf isn't running when a link is clicked, `librewolf -P private` starts that profile itself, outside the VPN. Start the private instance first, or don't click links in that window without it.
- **Overwriting saved tabs:** in a window started with `startup_session=none`, `Ctrl+Shift+S` (`save_as_session` in `kitty.conf`) still writes `~/.config/kitty/session.conf`, replacing the saved tabs with this window's.

The whole command, arguments in `open_url_with` included, was confirmed working by the user on 2026-10-10.
