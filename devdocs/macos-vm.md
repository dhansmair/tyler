# Running tyler in a macOS VM

A VM is a place to run tylerd where it can't touch the windows in use, and where switching the
Accessibility grant off can't freeze the machine. Nothing in the repository depends on one yet:
`design.md` (Testing) has the decision to run the end-to-end catalogue in a VM, which isn't built.

The tool is [Tart](https://github.com/openai/tart), on Apple's Virtualization.framework. Its
licence is FSL-1.1-ALv2, which allows anything but a competing commercial product. macOS lets two
macOS VMs run at once on one Mac.

## Setting one up

On the host:

```bash
brew install openai/tools/tart
tart clone ghcr.io/cirruslabs/macos-tahoe-base:latest tyler-dev   # about 25 GB
tart set tyler-dev --cpu 6 --memory 12288 --display 1920x1080
tart run --capture-system-keys tyler-dev
```

The guest logs in by itself as `admin`, password `admin`. The image has Homebrew and a Swift 6
toolchain. In the guest:

1. Clone tyler onto the guest's own disk, not a shared folder, and run `make build`.
2. Give the terminal the Accessibility permission, then reopen it.
3. Run `.build/debug/tyler start`.

Shut the guest down and keep a copy to go back to: `tart clone tyler-dev tyler-dev-clean`.

## Which way to run it

| | `tart run` | `tart run --vnc`, with Screen Sharing |
|---|---|---|
| Displays | One | Two, side by side |
| Speed | Direct | Clearly slower to use with two displays |
| For | Everyday use | Work on several displays |

## Input from the host

The host's event taps see input aimed at the VM's window, so a tylerd and a hotkey daemon on the
host act on it too:

- A hotkey daemon takes the keys before the guest gets them. skhd's `.blacklist` lets them through
  while the VM is in front: list `"tart"` and, with `--vnc`, `"screen sharing"`. Host hotkeys then
  don't work until a host window has the focus.
- A swipe over the VM's window reaches the host's gesture tap with its touches (measured), so a
  host tylerd can act on it. Turn `gestures.swipe` off on the host to be sure it doesn't.

## Running commands in the guest

`tart exec tyler-dev <command>` needs no ssh or keys. The command runs as the logged-in user in the
GUI session (`launchctl managername` says `Aqua`). A tylerd started this way saw the windows and a
probe opened an event tap; which grant allowed that wasn't found out.

## What was measured

On 2026-10-31, with Tart 2.41.1 on a macOS 26.7 host and a macOS 26 guest.

**A swipe reaches the guest without touches**, so swipes stay a check on real hardware. A
listen-only tap for gesture events read the same three-finger swipes on host and guest at once: 264
of the host's 2,378 events had three touches, and all 12,971 of the guest's had none, from both
`touches(matching:in:)` and `allTouches()`. The guest's events have a few fixed sizes (224 to 404
bytes, the host's reach 1,208), so no field looks like it holds the fingers. Starting the VM with
only the trackpad device (`tart run --suspendable`) gave the same: 0 touches in 296 events.
Two-finger scrolling and pinching work in the guest's apps, so the guest does get gestures, as
finished ones.

**`tart run --vnc` with a Screen Sharing client gives a second display.** The guest reported two
1920x1080 "Screen Sharing Virtual Display"s side by side, where the default view has one. tylerd
numbered both, tiled a workspace on the second and switched workspaces there. With the second
display on the right, it parked the first display's windows past its left edge (x = -950) and the
second's past its right edge (x = 3839), the sides that touch no display. `tyler debug windows`
showed no differences. These are the frames tylerd reports; they weren't compared on screen. The
displays come from the Screen Sharing session, so nothing yet opens them without a person.

## What a VM can't show

Swipes, plugging a display in, the lid, and anything measured on a virtual display until it is
checked against real hardware. Other arrangements of the two displays weren't tried.
