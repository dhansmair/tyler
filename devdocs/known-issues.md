# Known issues

Bugs, limitations and things not built, so nobody mistakes them for features. Each is a
[GitHub issue](https://github.com/dhansmair/tyler/issues), which holds the details; this list
indexes them. The strip layout's are in `strip-layout.md`. A commit that fixes one closes it
(`Fixes #<n>`) and removes its line here, and from `docs/known-issues.md`, which says the same
for users. A new one gets an issue and a line here.

## Bugs

- [#3](https://github.com/dhansmair/tyler/issues/3) Revoking Accessibility while the mouse button interceptor is armed can stop all input
- [#4](https://github.com/dhansmair/tyler/issues/4) An Option-click made before the interceptor is armed goes to the app
- [#5](https://github.com/dhansmair/tyler/issues/5) A Firefox window of a parked workspace was seen at x = 0 instead of its parking spot
- [#6](https://github.com/dhansmair/tyler/issues/6) Windows of a busy app can go untracked at attach
- [#7](https://github.com/dhansmair/tyler/issues/7) An Option-click can be lost when the mouse button interceptor is turned off mid-press
- [#8](https://github.com/dhansmair/tyler/issues/8) A minimized window can stay tiled
- [#9](https://github.com/dhansmair/tyler/issues/9) Finder windows made by AppleScript were tiled, later listed as dialog
- [#10](https://github.com/dhansmair/tyler/issues/10) Find out what a stale Accessibility entry looks like to tylerd
- [#11](https://github.com/dhansmair/tyler/issues/11) Echo tracking can go stale when an app never sends a focus event
- [#87](https://github.com/dhansmair/tyler/issues/87) Focusing a window can slide another display to the same app's parked window
- [#72](https://github.com/dhansmair/tyler/issues/72) A window opened in the background on an assigned workspace brings that workspace into view
- [#74](https://github.com/dhansmair/tyler/issues/74) A window moved alone onto a larger display arrives clamped to the old display's width

## Limitations

- [#13](https://github.com/dhansmair/tyler/issues/13) With the Dock on the left, windows parked at the left edge show a 56-point strip
- [#14](https://github.com/dhansmair/tyler/issues/14) On a display with a neighbour beside it, workspace switches are instant
- [#15](https://github.com/dhansmair/tyler/issues/15) The middle display of three has no free edge to park at
- [#16](https://github.com/dhansmair/tyler/issues/16) The resize cursor over a gap relies on a private window server call
- [#17](https://github.com/dhansmair/tyler/issues/17) Display numbers follow position
- [#18](https://github.com/dhansmair/tyler/issues/18) After a crash or kill -9, parked windows stay parked until the next start
- [#19](https://github.com/dhansmair/tyler/issues/19) Native fullscreen windows, other Spaces and non-regular apps are left alone
- [#20](https://github.com/dhansmair/tyler/issues/20) An unresponsive app stalls tylerd for the Accessibility timeout
- [#21](https://github.com/dhansmair/tyler/issues/21) Option-drag inside apps is lost while the modifier is Option
- [#22](https://github.com/dhansmair/tyler/issues/22) Terminals and windows with a minimum size don't fill their slot exactly

## Not built

- [#23](https://github.com/dhansmair/tyler/issues/23) Start tylerd at login (tyler service install)
- [#24](https://github.com/dhansmair/tyler/issues/24) Float rules in the config
- [#25](https://github.com/dhansmair/tyler/issues/25) Animate snapshots instead of windows (ScreenCaptureKit)
- [#26](https://github.com/dhansmair/tyler/issues/26) Signed releases
- [#28](https://github.com/dhansmair/tyler/issues/28) A cursor that shows a window can be dragged while the modifier is held

## Not tried

- [#42](https://github.com/dhansmair/tyler/issues/42) Not yet tried: older macOS, Intel Macs, three displays, long sleeps
