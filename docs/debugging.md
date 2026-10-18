# Debugging scripts

Quarry debugs a Doom 3 mod's scripts in a running game, with the views of
Xcode's debugger and the behaviour of VS Code's.

Quarry's side is UDCodeKit's debugger UI: breakpoints in the editor's
gutter, the debug bar, the debug navigator, the variables view and the
console. The game's side is `udscript-dap`, a Debug Adapter Protocol adapter
that Quarry carries beside its executable. It speaks the debugger protocol
built into dhewm3: UDP on ports 27980 and 27981, as the engine's own
Windows debugger does.

## Setting it up

1. Get a dhewm3. Our fork,
   [ashalkhakov/dhewm3](https://github.com/ashalkhakov/dhewm3), gives
   everything below. Stock dhewm3 1.5.5 works too, with what's listed under
   [With stock dhewm3](#with-stock-dhewm3).
2. In Quarry, open the workspace of your mod, then Workspace Settings >
   Debugging. Choose the game's executable (on macOS, its `dhewm3.app`), and
   add any arguments it should start with, such as `+map game/mars_city1`.
3. Set breakpoints in a script's gutter, or with Debug > Toggle Breakpoint
   (⌘\\).
4. Debug > Run (⌘R) starts the game with its debugger server on and your
   breakpoints set. Debug > Attach connects to a game you've started
   yourself with `+set com_enableDebuggerServer 1`.

When the game stops, Quarry comes forward with the debug navigator showing.
When you continue, a game that Quarry started comes forward again.

## What there is

- **Breakpoints** with conditions, hit counts and log messages (logpoints),
  edited from the gutter and listed in the Breakpoints navigator. Run to
  Cursor (⌃⌘C).
- **Stepping:** over (F6), into (F7) and out (F8). A step stays in its
  thread: other script threads run meanwhile, and the step ends in the
  thread it began in.
- **Threads and their call stacks** in the debug navigator, with each
  thread's state (waiting, ending).
- **Variables** of the selected frame. A method's `self` opens to its
  object's fields and its superclasses', and an entity opens to its script
  object's fields and its spawn args. Values that changed since the last stop
  are blue, and a filter narrows the list.
- **Expressions** in watches, hovers and the console: idScript's operators
  over variables, numbers, strings and entities, with `self.field` and a
  vector's `.x`, `.y` and `.z`. In the console, anything that isn't an
  expression goes to the game as a console command (`/` forces one).
- **Script errors and warnings** stop the game where they happen, before it
  handles them, as Xcode's exception breakpoints do. Turn them on and off in
  the Breakpoints navigator (Script Errors is on by default). Continuing
  after an error still drops the map, as the game does.
- **Setting a variable** from the variables view (double-click its value).
- **Jump to Cursor:** the stopped thread goes on from another line of the
  function it is in.
- **Restart:** Debug > Run while debugging ends the game and runs it again.

## With stock dhewm3

dhewm3 1.5.5's debugger protocol has no step out, and its steps can be ended
by any thread. It can't list a function's variables, and some requests abort
the game. `udscript-dap` makes up for what it can:

- it steps with temporary breakpoints;
- it reads variable names from the scripts and asks the game for each value;
- it reads a method's fields from the scripts' object declarations;
- it never asks a namespace's function for a name the game would abort on.

So breakpoints, stepping, step out, the stopped thread's variables and
`self`'s fields, watches and expressions all work. Our fork adds the rest:
stopping at script errors, other threads' stacks and variables, entities'
spawn args, setting a variable, Jump to Cursor, and `self` shown as its
entity (1.5.5 shows only its type). Quarry tells you when a request needs
it.

## How it works

The adapter asks the game for what it supports when it connects
(`DBMSG_VERSION`, our fork's protocol 2), and uses the engine's own steps,
variable lists and the rest when it can. The protocol's messages are in
dhewm3's `neo/tools/debugger/DebuggerMessages.h`. Our fork's additions are
appended to them, so the engine's original debugger keeps working.
