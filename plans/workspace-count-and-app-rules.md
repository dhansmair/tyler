# Workspace count and app assignments (M6)

## Context
The user (2026-10-10): make the number of workspaces dynamic and configurable, four by default,
and let the config send an app's windows to a workspace ("Firefox always spawns on workspace 3").

## 1. Workspace count
```toml
[workspaces]
count = 6        # 1 to 10, default 4
```
- `WindowManager` takes the count from `Config` (the `workspaceCount` init parameter goes).
- "Dynamic" means `reload` applies a new count without a restart:
  - Growing appends empty workspaces with the configured gaps.
  - Shrinking merges the windows of the removed workspaces into the new last workspace, after
    its own windows, in order. If the current workspace was removed, the new last one becomes
    current. The current workspace then re-tiles, so merged windows that were parked come into
    view if they landed on it. No slide: the change is a config edit, not a navigation.
- A restart keeps the count from the config; `SavedState.stack(count:)` already drops or adds
  workspaces. It drops windows beyond the count. Change that to merge them the same way.
- The menu bar, `workspace <n>` range errors and `list` already use `workspaces.count`.

## 2. App assignments
```toml
[assign]
Firefox = 3                  # app name, as `tyler list` shows it
"com.mitchellh.ghostty" = 2  # or bundle ID (quoted, because of the dots)
```
- A key matches a window whose bundle ID or app name equals it (case-insensitive). The value is
  a workspace number within `workspaces.count` of the same file, otherwise the file is invalid.
- **Only new windows**: a window goes to its assigned workspace the first time it joins tiling
  (when it opens, or for windows already open when tylerd starts). After that it behaves like any
  other window: `move-to-workspace` moves it, and un-floating, un-minimizing or leaving fullscreen
  bring it back on the current workspace as today. tylerd tracks which windows have been
  tiled (`WindowManager.seen`) for this; `SavedState` carries it across a restart.
- A window assigned to a workspace that isn't on screen is parked there directly, without a slide.
  If the app focuses it (usual for a new window), the existing rule "focusing a parked
  window shows its workspace" switches there. A window opened in the background (no focus) just
  parks. This also keeps keystrokes from going to a parked window.
- Only windows on the primary display are assigned (same as newcomers today; M5 changes this).
- `reload` applies new rules to windows opened afterwards; it doesn't move existing windows.
