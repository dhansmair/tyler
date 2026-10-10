Yes, I can build that. A basic tiling/floating window manager with keyboard navigation is a realistic project in Swift. Before writing anything I need to know what you want that AeroSpace and Amethyst don't give you, because that decides the design.

How it would work

- Moving and resizing windows: macOS's Accessibility API (AXUIElement). The app needs Accessibility permission once. You don't have to disable SIP; that's only needed for yabai-style tricks.
- Keeping track of windows: the app subscribes to macOS events for windows being created, destroyed, moved, resized or focused, and for apps launching and quitting. That keeps its own list of windows up to date.
- Global hotkeys: Carbon RegisterEventHotKey, or a CGEventTap if you want modal keys, key chords or mouse bindings.
- Focus and navigation: pick a window by geometry (left, right, up or down), then raise it and activate its app.
- Packaging: a small menu-bar app built with SwiftPM, set up with a plain config file (TOML or similar) that it reloads when the file changes.

Limits macOS imposes

- Native Spaces can't be controlled reliably without private APIs or turning off SIP. AeroSpace gets around this by running its own virtual workspaces and parking hidden windows off-screen. If you want workspaces, we'd most likely do the same.
- Some apps don't cooperate. They enforce a minimum size, refuse a resize, or animate slowly. Terminals often snap their size to whole character cells.
- Native fullscreen windows live on their own Space and are out of reach.
- Moving many windows at once is a bit slow. Each window is a separate call to the app that owns it, so a full re-tile can visibly lag.

What I need from you

1. What's missing: which behaviours do the existing tools get wrong, or not offer at all? Concrete examples help most, like "I want X to happen when I press Y".
2. Tiling model: a manual tree like i3 or AeroSpace, automatic layouts like Amethyst's master/stack, or something of your own?
3. Floating: should floating be the default with tiling on request, or the other way round? Should particular apps always float?
4. Workspaces: do you need them at all? If so, are virtual workspaces fine?
5. Multiple monitors: does it need to handle them?

Once you've answered, I'll write a short design, then build a minimal working version first (enumerate windows, a tile command and directional focus) and add features from there.

✻ Cogitated for 53s · done 10:22 PM

❯ tiling model: I want something similar to xmonad. I usually have at most two windows open side by side. Sometimes I do have one on the left and two on the right above each other. That is all I would need for the beginning, but it should be extensible. But I like to think about the layout as a "list" of windows with a clear 'prev' and 'next' order. I also want to have multiple virtual monitors, like aerospace for example has. Virtually, I want them to sit "on top of each over". I want to be able to vertically scroll through the monitors, with a snapping effect.

  Build a cli tool. There should be sort of a background server and a cli with which I can send commands to the background server. Probably, swift would be the best language for this

  Ran 1 shell command

⏺ Streaming response ended before any complete data was received. Retrying without streaming. If this keeps happening, check any proxy or gateway between Claude Code and your model provider.
Interrupted · What should Claude do instead?

❯ are you there?

Yes, I'm here. So far I've only checked the toolchain: Swift 6.3 with Command Line Tools on macOS 26.6, and the project directory is empty. I haven't written anything yet.

Here's what I plan to build, so you can correct it before I start:

Two binaries from one Swift package
- mwmd, the background server. It tracks windows through the Accessibility API, applies layouts, owns the virtual monitors, and listens on a Unix socket at ~/.mwm/mwm.sock.
- mwm, the command-line client. It sends one command per call, like mwm focus next, mwm swap prev, mwm layout tall, mwm monitor 2, mwm move-to-monitor down or mwm float toggle, and prints the reply. You bind keys to it with skhd or similar, and you can script it.

Layout (xmonad-style)
- Each virtual monitor holds an ordered list of windows. That gives you a clear "next" and "prev" for focus and swapping, plus a "master" (the first window).
- A Layout protocol takes a list of windows and a screen rectangle and returns a frame for each window, so new layouts are just new types. I'd start with:
  - tall: master on the left, the rest stacked on the right. With two windows that's side by side; with three it's one left and two on the right.
  - full: one window fills the screen.
- Floating windows sit outside the list and the layout leaves them alone.

Virtual monitors stacked vertically
- They're arranged top to bottom like pages. Windows on the active one are at their normal positions, and the others are pushed off-screen above or below, the same trick AeroSpace uses.
- Scrolling between them animates every window vertically, then settles on the nearest monitor (the snapping).

One question: what should trigger the scroll?
- (a) Only the CLI (mwm monitor down), animated with a slide and snap.
- (b) A trackpad or mouse-wheel scroll while you hold a modifier key, where the windows follow your fingers and snap into place when you let go.

Option (b) needs an event tap, and moving lots of windows live through the Accessibility API can get choppy. I'd build (a) first and add (b) on top once it works.

Should I go ahead on that basis?

✻ Cogitated for 12s · done 10:41 PM

❯ you where thinking for 12 minutes, what happened?

I can't tell what took 12 minutes. From my side, all I did was run one quick command to check the Swift version, the Xcode tools path, the macOS version and the empty project folder. Its result came back, and then your interrupt arrived. Nothing visible to me ran in between. The delay was probably on the service side (slow generation or a stalled request), not work I was doing. Nothing was written or changed.

We're where my last message left off. The plan is a mwmd background server plus an mwm command-line tool talking over a Unix socket, xmonad-style window lists with tall and full layouts, and virtual monitors stacked vertically.

The one open question is how scrolling between monitors should work. I'd start with CLI-driven scrolling (mwm monitor down) with a slide-and-snap animation, and add trackpad scrolling with a modifier key later. If that's fine, I'll start building.
