---
track: A
prio: 40
type: bug
blocked-by: []
summary: "Five Makefile guards check the pinned stable with `test -x`, which tests the executable BIT — a property of the file, not of whether this CPU can run it. On a non-x86-64 host every guard reports healthy and the recipe then dies at exec with `Exec format error`, after printing a message saying there is no pinned stable at a path where one demonstrably is. Found on `via` (aarch64), where the repo ships only `stable_linux_amd64`. A reader would reasonably conclude the checkout is broken."
status: backlog
---

# `test -x` on the pinned stable passes on a foreign architecture

Found 2026-08-27 by the `ianweb` session on `via` while scoping whether that
host could meet Track D's snippet-verification gate. Verified independently in
`/home/neo/frank2`.

## The measurement

`via` is **aarch64**. The repo ships **only** `stable_linux_amd64`:

```
$ uname -m
aarch64
$ file stable_linux_amd64/default/stable_pinned
ELF 64-bit LSB executable, x86-64, statically linked
$ ./stable_linux_amd64/default/stable_pinned --version
cannot execute binary file: Exec format error
```

The guard, `Makefile:3485` in `seed-from-stable`:

```make
@test -x $(PXX_STABLE) || \
  (echo "No pinned stable at $(PXX_STABLE). Run: make bootstrap (needs FPC) once."; exit 1)
cp $(PXX_STABLE) $(COMPILER)
```

**`test -x` passes.** The file exists and carries the executable bit — and that
bit is a property of the file, not a statement about whether this CPU can run
it. So the precondition check reports healthy, the recipe proceeds, and the
failure surfaces later at the exec.

## Why this is worth a ticket rather than a shrug

The diagnostic is not merely absent, it is **actively misleading**. The only
message a reader gets says *"No pinned stable at `stable_linux_amd64/default/pinned`"*
about a path where a pinned stable is demonstrably present and executable-bitted.
The reasonable conclusion is "my checkout is broken", and the actual answer is
"this binary is for another architecture" — a different problem with a different
fix. On `via` the fallbacks are shut too: no `qemu-x86_64`, nothing in
`binfmt_misc`, no FPC, so the suggested `make bootstrap` escape hatch cannot run
either.

**Five sites, not one** — the same guard is repeated, so a fix wants to be one
helper rather than five edits:

```
Makefile:3485    seed-from-stable
Makefile:12631   test-fpjson
Makefile:13695
Makefile:13796
```

(plus `13769`, a `test -f` on the managed-stable dir, same family.)

## Suggested shape

Keep `test -x` as the first check — it still catches the genuinely-missing case
— and add an architecture check when it passes. Cheapest sufficient form is to
actually run the thing: `$(PXX_STABLE) --version >/dev/null 2>&1`, and on
failure emit a message that distinguishes the two causes and names
`uname -m` versus the binary's target. A `file`-based check works too but adds a
dependency the Makefile does not currently have.

Whatever the shape: **the message must separate "absent" from "present but
foreign".** That is the entire value of the ticket.

## Scope note — this is the diagnostic, not the port

Making pxx *work* on aarch64 hosts is a different and larger question (publish
an aarch64 stable, or document `qemu-user-static`), and it is A/T work that
would help more than one host. See the lane bound recorded in
`devdocs/dev/session-roster.md` for `via`'s situation. **This ticket is only
about the guard lying.** Do not widen it into the port.

## Why it was found at all — the day's recurring shape

`test -x` answers *"is this file flagged executable"* and was read as *"can this
machine execute it"*. Those are near-neighbour questions and the instrument
returns success either way, which is what makes it invisible. Third instance in
one day of the same failure — see the standing rule in the roster.
