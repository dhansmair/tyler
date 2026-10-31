# 2026-10-31: new windows on the focused display

A run between releases, for the rule that a new window joins the workspace in use, and for the review
fixes of the focus staying on its display; the catalogue's rows weren't run.

- Date: 2026-10-31
- macOS: 26.7.2
- Build: 8798eba
- Displays: the built-in display, an external display above it
- Skipped contexts: displays side by side

By hand, with terminals opened by a shortcut running `open -n` on an empty workspace of the built-in
display, then closed one by one, over about a minute: about 10 windows. Each joined that workspace,
also the one opened after the workspace had been left empty. No workspace switched, tylerd declined
3 focuses on the other display, and no placing or focusing failed.

The window shows on the other display for a moment before it moves. It is noticeable, and acceptable.

Not run: an app restoring windows at launch, and an app with an assigned workspace.
