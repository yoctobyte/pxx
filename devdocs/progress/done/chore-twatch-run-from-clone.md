---
prio: 50
---

# The watcher daemon executes the DEV CHECKOUT's twatch.py while testing the clone

- **Type:** chore (watcher deployment hygiene). **Track T.**
- **Found:** 2026-07-20, while restarting the borg watcher.

## What
`trackt start` launches the daemon from `HERE` — the directory of the
`trackt.py` that was invoked — not from the clone it tests:

```python
cmd = [sys.executable, os.path.join(HERE, "twatch.py"), "--clone", clone]
```

So running `./trackt start` from `~/trackt` gives:

```
python3 /home/rene/trackt/tools/twatch.py --clone /home/rene/trackt-watch
```

The daemon's own code comes from a **working tree that agents edit live**,
while the code under test comes from the dedicated clone. Editing
`tools/twatch.py` in the dev checkout silently changes what the watcher will
execute on its next start — including mid-refactor states that were never
committed, let alone tested.

## Why it matters
This is the same shape as the 2026-07-07 dirty-clone incident (watcher sharing
a checkout with a dev session, ingesting uncommitted edits, dying on publish),
which is why the watcher got a dedicated clone in the first place. The clone
fixed the *data* side; the *code* side still reaches into the dev tree.

Concretely: a T agent editing twatch.py, then restarting the daemon to pick up
a fix, is also shipping every other uncommitted edit in that file. Today that
was benign — the edits were committed first — but nothing enforces it.

## Suggested fix
Launch the daemon from the clone's own `tools/twatch.py`, so the watcher runs
committed code that arrived through `git pull` like everything else. Options:

1. `cmd = [sys.executable, os.path.join(clone, "tools/twatch.py"), ...]` —
   simplest, and makes "restart to pick up a fix" mean "pull, then restart",
   which is the correct mental model.
2. Keep launching from `HERE` but refuse to start with a dirty
   `tools/twatch.py` (or warn loudly), preserving the convenience of testing a
   local change deliberately.

Option 1 is the honest one; option 2 preserves a workflow T agents actually use
(edit, restart, observe). Possibly both: option 1 by default, option 2 behind
an explicit `--local-code` flag for deliberate testing.

## Non-goal
Not about `trackt run`, which already never touches the clone and is meant to
test the checkout.

## Log
- 2026-07-20 — resolved in 4e8674ac (option 1 + option 2: clone's copy by
  default, `--local-code` to opt back into the checkout's copy). The running
  daemon was deliberately NOT restarted for it — mid-cycle and healthy — so it
  takes effect at the next natural restart.
