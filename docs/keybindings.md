# Keybindings

tyler has no hotkeys of its own: every action is a `tyler` command, and you bind keys to those
commands with the tool you already use. This keeps tyler out of your keyboard: it never sees a key
press, so it can't clash with your apps or your key remapper.

Any tool that runs a shell command on a key press works. Three common ones are below. Each runs
commands without your shell's `PATH`, so call `tyler` by its full path: after `make install`,
`~/.local/bin/tyler` (`$HOME/.local/bin/tyler` where `~` isn't expanded).

Every command is described in the [command reference](manual.md#command-reference).

## A suggested set

A starting point in the style of xmonad, with Option (`alt`) as the modifier. Option with a letter
types special characters in macOS (Option+J is `∆`), so binding it takes those characters away in
every app; pick another modifier, such as Ctrl+Option, if you type them.

| Keys | Command |
| --- | --- |
| Option+J / Option+K | `tyler window focus next` / `tyler window focus prev` |
| Option+Shift+J / Option+Shift+K | `tyler window swap next` / `tyler window swap prev` |
| Option+Return | `tyler window swap master` |
| Option+H / Option+L | `tyler layout ratio -0.05` / `tyler layout ratio +0.05` |
| Option+Space | `tyler layout next` |
| Option+T | `tyler window float toggle` |
| Option+Shift+Q | `tyler window close` |
| Option+1 … Option+4 | `tyler workspace focus 1` … `tyler workspace focus 4` |
| Option+Shift+1 … Option+Shift+4 | `tyler window move-to-workspace 1` … `4` |
| Option+, / Option+. | `tyler display focus prev` / `tyler display focus next` |
| Option+Shift+, / Option+Shift+. | `tyler window move-to-display prev --follow` / `next --follow` |

## skhd

[skhd](https://github.com/koekeishiya/skhd) is a small hotkey daemon configured with a text file.
Install it with `brew install koekeishiya/formulae/skhd`, start it with `skhd --start-service`, and
grant it Accessibility permission when macOS asks. Put the bindings in `~/.config/skhd/skhdrc`:

```
alt - j : ~/.local/bin/tyler window focus next
alt - k : ~/.local/bin/tyler window focus prev
alt + shift - j : ~/.local/bin/tyler window swap next
alt + shift - k : ~/.local/bin/tyler window swap prev
alt - return : ~/.local/bin/tyler window swap master
alt - h : ~/.local/bin/tyler layout ratio -0.05
alt - l : ~/.local/bin/tyler layout ratio +0.05
alt - space : ~/.local/bin/tyler layout next
alt - t : ~/.local/bin/tyler window float toggle
alt + shift - q : ~/.local/bin/tyler window close

alt - 1 : ~/.local/bin/tyler workspace focus 1
alt - 2 : ~/.local/bin/tyler workspace focus 2
alt - 3 : ~/.local/bin/tyler workspace focus 3
alt - 4 : ~/.local/bin/tyler workspace focus 4
alt + shift - 1 : ~/.local/bin/tyler window move-to-workspace 1
alt + shift - 2 : ~/.local/bin/tyler window move-to-workspace 2
alt + shift - 3 : ~/.local/bin/tyler window move-to-workspace 3
alt + shift - 4 : ~/.local/bin/tyler window move-to-workspace 4

alt - 0x2B : ~/.local/bin/tyler display focus prev
alt - 0x2F : ~/.local/bin/tyler display focus next
alt + shift - 0x2B : ~/.local/bin/tyler window move-to-display prev --follow
alt + shift - 0x2F : ~/.local/bin/tyler window move-to-display next --follow
```

(`0x2B` and `0x2F` are the comma and period keys.) skhd reloads the file when it changes.

## Karabiner-Elements

[Karabiner-Elements](https://karabiner-elements.pqrs.org) can run a shell command from a complex
modification. Add a rule under Complex Modifications > Add your own rule, for example:

```json
{
  "description": "tyler: focus and workspaces",
  "manipulators": [
    {
      "type": "basic",
      "from": { "key_code": "j", "modifiers": { "mandatory": ["option"] } },
      "to": [{ "shell_command": "~/.local/bin/tyler window focus next" }]
    },
    {
      "type": "basic",
      "from": { "key_code": "k", "modifiers": { "mandatory": ["option"] } },
      "to": [{ "shell_command": "~/.local/bin/tyler window focus prev" }]
    },
    {
      "type": "basic",
      "from": { "key_code": "1", "modifiers": { "mandatory": ["option"] } },
      "to": [{ "shell_command": "~/.local/bin/tyler workspace focus 1" }]
    }
  ]
}
```

Add one manipulator per binding of the table above.

## Raycast

[Raycast](https://www.raycast.com) runs *script commands*: shell scripts with a few comment lines
that Raycast reads. Make a folder for them, add it under Settings > Extensions > Script Commands,
and put one script per command in it, for example `tyler-workspace-next.sh`:

```bash
#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Next workspace
# @raycast.packageName tyler
# @raycast.mode silent

~/.local/bin/tyler workspace focus next
```

Make it executable (`chmod +x`), then give it a hotkey in Raycast's settings. Raycast also lets you
run the commands from its search bar without a hotkey.
