# kitty cheatsheet

All shortcuts are `Ctrl+Shift+<key>` (= `kitty_mod`). Bindings live in
`home-files/kitty.conf`.

## Splits (panes inside a tab)

| Key                  | Action                                  |
|----------------------|-----------------------------------------|
| `\`                  | vertical split (right)                  |
| `-`                  | horizontal split (below)                |
| `Enter`              | new pane in current layout              |
| `h` / `j` / `k` / `l`| focus pane left / down / up / right     |
| `←` / `↓` / `↑` / `→`| swap pane with neighbor                 |
| `z`                  | zoom toggle (stack layout)              |
| `r`                  | resize mode — arrows, `Esc` to exit     |

## Tabs

| Key            | Action                          |
|----------------|---------------------------------|
| `t`            | new tab in current cwd          |
| `q`            | close tab                       |
| `n` / `p`      | next / previous tab             |
| `1` … `9`      | jump to tab N                   |
| `,`            | rename tab (`Ctrl+u` clears)    |
| `.`            | rename window (pane)            |

## Copy / paste

| Key                     | Action                                          |
|-------------------------|-------------------------------------------------|
| `c` / `v`               | copy selection / paste clipboard                |
| `u`                     | scrollback in nvim — `/`, `V`, `"+y`, `:q`      |
| `Space` then `l`        | hints: pick a line  (`--multiple` enabled)      |
| `Space` then `w`        | hints: pick a word                              |
| `Space` then `f`        | hints: pick a path                              |
| `Space` then `o`        | hints: pick a URL                               |
| `Space` then `g`        | hints: pick a git hash                          |

Hints workflow: highlighted matches get a single-letter label — type the
letter to copy. With `--multiple` (lines), tap several labels then `Esc`.

## Sessions

| Key            | Action                                                |
|----------------|-------------------------------------------------------|
| `s`            | overwrite `~/.config/kitty/session.conf` silently     |
| `F5`           | save-as prompt — for ad-hoc / named sessions          |

`startup_session ~/.config/kitty/session.conf` is set, so the default
file is replayed on launch. Splits / tabs / panes created via the above
bindings are session-aware (`--add-to-session=session:.` / `*_with_cwd`).

## Reload / misc

| Key            | Action                          |
|----------------|---------------------------------|
| `Ctrl+Shift+F5`| reload `kitty.conf`             |
| `Ctrl+Shift++` | font size up                    |
| `Ctrl+Shift+-` | font size down                  |
| `Ctrl+Shift+Backspace` | reset font size         |

## Files

- `kitty.nix` — installs kitty (wrapped with `nixGL` for non-NixOS GL)
  and `kitty-scrollback-pager`.
- `home-files/kitty.conf` — the runtime config (theme, bindings).
- `scripts/kitty-scrollback-pager` — strips ANSI escapes before piping
  scrollback into nvim.
