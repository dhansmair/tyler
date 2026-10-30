# Installing from source

The [README](../README.md#installation) installs tyler with Homebrew, which also builds it from
source. Building it yourself is for working on tyler, or for keeping the Accessibility permission
across updates with a signing identity of your own. It needs the same
[requirements](../README.md#requirements).

## Installing

```bash
git clone https://github.com/dhansmair/tyler.git
cd tyler
make install          # builds a release and copies tyler, tylerd and Tyler.app to ~/.local/bin
```

Add `~/.local/bin` to your `PATH` if it isn't there yet (for zsh, in `~/.zshrc`:
`export PATH="$HOME/.local/bin:$PATH"`). `make install PREFIX=/some/dir` installs elsewhere.

Built without a code-signing identity, `Tyler.app` is signed ad hoc, and macOS treats every update
as a new app: it asks for the permission again after each one. With an identity of your own (a
self-signed one is enough), `make install SIGN_ID=<identity>` keeps the permission across updates;
set `SIGN_ID := <identity>` in a `local.mk` next to the `Makefile` to use it for every build.

Then start it with `tyler start`, as in the [README](../README.md#installation).

## Updating

```bash
git pull
make install
tyler restart         # windows stay where they are
```

## Development builds

`make build` builds into `.build/debug`. With `SIGN_ID` set it builds `Tyler.app` there too, and
`.build/debug/tyler start` runs it where it is. Without `SIGN_ID` it builds no app, and the bare
`tylerd` runs under the permission of the terminal that starts it: start it from a terminal app
that has the Accessibility permission. The [manual](manual.md#running-tylerd) has the details.

## Switching between installs

With several installs (Homebrew, `make install`, a checkout), `devtools/tyler-use` picks one:

```bash
devtools/tyler-use brew      # the Homebrew install
devtools/tyler-use local     # what make install copied to ~/.local/bin
devtools/tyler-use main      # the main checkout's .build/debug
devtools/tyler-use ../other  # another checkout, or a folder holding tyler and tylerd
devtools/tyler-use           # which is active, and what runs
```

It links `~/.tyler/current` to that install and restarts `tylerd` from it. Put the link first on
your PATH, at the end of your shell's startup file, so `tyler` is always the chosen install:

```bash
export PATH="$HOME/.tyler/current:$PATH"
```

A hotkey daemon such as skhd has a PATH of its own: use `~/.tyler/current/tyler` in its bindings,
since a release may change the socket protocol. Each install has its own Accessibility permission,
and going to another one puts the windows back until it has that permission, as `tyler restart`
says. An older install can't read the state of a newer one: `tyler stop` first if the windows stay
parked.

## Uninstalling

```bash
tyler stop                                   # puts every window back
tccutil reset Accessibility io.github.dhansmair.tyler   # Tyler.app's permission
rm -r ~/.local/bin/tyler ~/.local/bin/tylerd ~/.local/bin/Tyler.app ~/Applications/Tyler.app
rm -r ~/.tyler ~/.config/tyler               # the socket, log and config
```

Reset the permission before deleting the app: `tccutil` only finds an app that is still there.
Without `Tyler.app`, remove your terminal from the Accessibility list instead, if nothing else
needs it.
