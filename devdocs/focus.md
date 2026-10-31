# Focus: who chose this window?

What tyler wants from focus, and which real situations each rule exists for. The code holds the
logic (`ParkedFocusVerdict`, `WindowEventInterpreter`, `WorkspaceController.focusSettled`), the
values are in `delays-and-heuristics.md`, and the measurements in `macos-behaviour.md`. Read this
before changing how tyler reacts to a focus. Keep it current: a new case gets a row, and a gap that
closes moves into the table.

## What the user wants

1. **A workspace moves only when the user went there.** A click, cmd-tab or cmd-` to a window on a
   parked workspace brings it into view.
2. **Keys always reach a window the user can see.** When tyler refuses a move, it also takes the
   focus off the parked window.
3. **Focus stays on the user's display until they move it,** by a focus or, with focus follows
   mouse on, by resting the pointer on an empty workspace. What they type or open next belongs
   there, even if a close leaves its workspace empty. A window that opens joins the workspace the
   user is on, wherever macOS or the app put it, unless its app is assigned to a workspace.

## Why it is hard

macOS sends one message: this window now has the focus. The message is the same whether the user
chose the window, an app passed through it, or macOS picked it because something closed. It never
says who did it. So every rule answers one question, **who chose this window?**, from three clues:

- **Did the focus last?** Apps pass through a remembered window for a few milliseconds.
- **Did the window that held the focus go away?** Then macOS picked the next one.
- **Had tyler just asked that app for another window?** Then the app went to the window it remembers.

When a clue is wrong, the usual result is a workspace switch nobody asked for. Keys left on a parked
window is the worse failure, so when in doubt tyler follows the focus.

## The cases

The test shows each one; a stale name here means this page needs a look. Those without a real-window
check have only run on fakes.

| The user did | macOS does | Who chose | tyler | Test | On real windows |
|---|---|---|---|---|---|
| Click, cmd-tab or cmd-` to a parked window | Focuses it | The user | Follows | `aFocusThatLastsBringsItsWorkspaceIntoView` | Yes |
| Focus a window of an app with another window on the other display | Passes through the remembered window | The app, in passing | Ignores it | `aPassingFocusOnAParkedWindowSwitchesNothing` | Yes |
| The same, right after that other window was swiped away | Ends on the remembered window | The app | Asks again, once | `tylerdAsksAgainInsteadOfSwitching` | Yes |
| Close a window, the app has another one parked | Focuses the parked one | macOS | Declines, focuses the current workspace | `aCloseThenAFocusOnAParkedWindowStaysAndFocusesTheSibling` | Yes |
| Close a window with another in view on the other display | Can focus that one | macOS | Declines, keeps the focus on the display, even on an empty workspace | `aCloseKeepsTheFocusOnItsDisplay` | Yes |
| Quit an app with a window in view on the other display | Can focus that one | macOS | Declines | `aQuitKeepsTheFocusOnItsDisplay` | No |
| Quit an app, another app's window is parked | Focuses it, possibly before the quit reaches tyler | macOS | Declines | `aFocusThatComesBeforeTheCloseAlsoStays` | Yes |
| A close leaves the workspace empty | Focuses a parked window | macOS | Declines, takes the focus away | `theWorkspaceLeftEmptyStaysAndTakesTheFocusAway` | Yes |
| Close an app's last window, later cmd-tab to a parked window | Focuses nothing, then that window | The user | Follows | `aFocusLongAfterTheCloseSwitches` | Yes |
| Open a window that appears on the other display | Focuses it there | The user | Moves it to their workspace; its first focus doesn't move the display | `itsFocusDoesNotMoveTheFocusedDisplay` | Yes |
| Rest the pointer on an empty workspace on another display | Nothing | The user | Focuses that workspace, keys included | `aRestOnAnEmptyWorkspaceTakesTheKeys` | Yes |
| Drop a tab torn off a browser on the other display | Opens a window there, after the button comes up | The user | Leaves it there, as it opened under the pointer | `aWindowOpeningUnderThePointerStaysWhereItOpened` | Yes |
| tyler focuses a window | Reports that focus back | tyler | Ignores it | `theEchoOfTylerdsOwnFocusDoesNotSwitchBack` | Yes |
| A background window closes, then a focus on a parked window | Focuses it | The user | Follows | `aBackgroundWindowClosingTakesNothingAway` | No |
| A dialog closes and its app focuses a parked window | Focuses it | The app, on purpose | Follows | `aDialogClosingAndFocusingAParkedWindowSwitches` | No |
| The app ignores tyler's second request | Stays on the parked window, or says nothing | The app | Follows, so keys don't stay hidden | `aSecondAskThatChangesNothingIsFollowed` | No |

## What isn't covered

- **Cmd-H and cmd-M:** macOS may pick a parked window the same way, but nothing closed, so tyler
  follows. Not measured.
- **cmd-` just after tyler focused that app:** it is taken for the app ending on its remembered
  window and asked back once. The next press goes through.
- **Windows an app restores when it launches** count as new, so they all join the display the user
  is on. So do older windows tracked late (#99).
- **With focus follows mouse off,** moving the pointer to another display doesn't focus it, so a
  window opened then goes to the display that had the focus.
- **`open -g`** can bring an assigned workspace into view (#72).
- **A floated window on a workspace left empty:** it could take the keys after a decline, but
  nothing gives it the focus.
- **An expected focus that never comes** goes stale, and a later real focus is taken for tyler's own
  (#11).
- **A close whose focus arrives before the close does,** with the next window in view on another
  display: the check there has no wait, so the focus is followed. Not seen; quits are caught by the
  window server.
- **The app ending on another window than tyler asked for, in view on another display:** the focus
  is followed. The second request only covers parked windows.
- **A floated window on another display taking the focus after a close** keeps it, while commands
  stay on the old display.
- **A dialog holding the focus when its app quits:** only standard windows count as gone, so tyler
  follows.
