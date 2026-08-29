---
track: D
prio: 30
type: docs
blocked-by: []
summary: "{$NILCHECKS ON|OFF} and --no-nil-check shipped 2026-08-21 and are not in docs/reference/directives.md or modes.md. The row is unusual enough to be worth a sentence: the directive is tri-state, so ON and OFF do different things depending on which site class you are looking at."
status: done
owner: frankD
---

# Document `{$NILCHECKS}` and `--no-nil-check`

Landed 2026-08-21 by [[feature-a-emitted-nil-checks]] (Track A). Filed for D
because `docs/**` is D's lane; the compiler side is done and green.

## The row

`docs/reference/directives.md`, in the checking-directives table next to `{$R}`
/ `{$Q}` / `{$I}`:

| Directive | Effect | Default | Flag |
| --- | --- | --- | --- |
| `{$NILCHECKS ON\|OFF}` | Nil-pointer checking. | see below | `--no-nil-check` |

## Why it needs a sentence and not just a row

The Default column cannot hold the answer, because there isn't one answer. The
directive is **tri-state** — the compiler distinguishes "on", "off" and *"the
author said nothing"* — and the two site classes resolve the third state in
opposite directions:

- **calls** — a method on a nil instance, a call through a nil procvar or
  method pointer, a method on a nil interface: **checked by default**. The
  check costs ~2% and replaces a fault that lands frames away from the call
  (or, on a target with no signal runtime, does not land at all).
- **bare pointer derefs** — `p^`, `p^.f`, `p^[i]`: **not checked by default**,
  because that is a test inside whatever loop the deref sits in and on the PC
  targets the MMU already reports it at exactly the right instruction. Measured
  +6% on a loop that does nothing else.

So `{$NILCHECKS ON}` *adds* the deref checks, `{$NILCHECKS OFF}` *removes* the
call checks, and each is a no-op for the other class. `--no-nil-check` is the
master off for both.

What a checked site does when it fires: calls `PXXNilRef`, which prints
`Runtime error 216 (nil reference)` and halts — or, with `SysUtils` in the
program, raises a catchable `EAccessViolation`. **That catchability is the
point of the feature**, and is worth saying in the prose: it is what a raw
memory fault can never offer, since `try..except` does not run for one.

`docs/reference/modes.md` wants the `--no-nil-check` line too.

## Gate

D's usual: prose consistent, and any snippet compiles against `$(PXX_STABLE)`.
Note the pin must be v369 or later for the examples to build at all.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.

---

## RESOLVED 2026-08-29 (frankD)

Three pages. Every claim in the ticket was reproduced against pinned **v392**
before it was written down; all of them held, and two details the ticket did not
mention turned up.

### Where it went

- **`docs/reference/directives.md`** — the row in the Check switches table beside
  `{$I}`/`{$R}`/`{$Q}`, then `### {$NILCHECKS} is tri-state`. The Default column
  says `tri-state — see below` rather than pretending to an answer, and the prose
  carries a 3x2 table (calls / bare derefs × said-nothing / ON / OFF) because the
  asymmetry is the whole content of the feature. Then `### What a checked site does
  when it fires`, with the catchability contrast as a runnable example.
- **`docs/reference/cli.md`** — `--no-nil-check` in `## Runtime and codegen`, next
  to `--no-div-check`, which is its exact sibling (a default-on emitted check with
  an opt-out flag).
- **`docs/reference/modes.md`** — see below; not the plain line the ticket asked
  for, and the reason is recorded.

### The catchability claim, made runnable instead of asserted

The ticket says catchability "is the point of the feature". That is worth more
than a sentence, so the page shows **one program that demonstrates both halves**:
a `try..except` around `WriteLn(p^)` with `SysUtils` in scope segfaults with the
`except` never running, and the *identical* source with `{$NILCHECKS ON}` added
after the `uses` clause prints `caught: EAccessViolation` / `still running` and
exits 0. Both were run; the snippet in the page was extracted from the rendered
Markdown and compiled, and its `{$NILCHECKS ON}` variant produced exactly the
output the page claims.

### Two things the ticket did not say, both measured

1. **`--no-nil-check` outranks the directive.** A source that says
   `{$NILCHECKS ON}` still gets no deref check under the flag — verified: the
   same program segfaults. "Master off for both" understates it; it is master off
   over an explicit opt-in too, which is the part someone debugging would trip on.
2. **The two failure messages differ, and the difference is informative.** Halting
   prints `Runtime error 216 (nil reference)`; the exception is
   `EAccessViolation: Access violation (nil reference)` — the parenthetical is
   what separates it from an ordinary access violation. Both are quoted, and both
   were string-compared against real program output rather than checked by eye.

### `modes.md` — a note on the axis, not a line in the switch table

The ticket asked for "the `--no-nil-check` line too". Adding it to that page's
granular-switch table would have been wrong: every switch there decides whether a
**program is accepted** (dialect strictness), while a nil check is emitted code
that fires at **run time**. Dropping a runtime knob into that table blurs the
model the page exists to state, and `--strict`/`--mimic-fpc` do not touch nil
checks at all.

So the page gets `### Runtime checks are a separate axis` instead — a five-row
table of the runtime checks (`{$R}`, `{$Q}`, `{$I}`, `{$NILCHECKS}`,
`--no-div-check`) with their defaults, saying plainly that they are not part of
the strictness umbrellas. That satisfies what the ticket wanted (a reader of
modes.md learns the flag exists) without damaging the page. Flagged here because
it is a deliberate deviation from the ticket's wording, not an oversight.

### Measured — pinned v392, no rebuild

| case | result |
| --- | --- |
| call on nil instance, default | `Runtime error 216 (nil reference)`, exit 216 |
| same, `--no-nil-check` | runs, exit 0 |
| same, `{$NILCHECKS OFF}` | runs, exit 0 |
| `p^` deref, default | SIGSEGV, exit 139 |
| same, `{$NILCHECKS ON}` | `Runtime error 216`, exit 216 |
| same, `{$NILCHECKS ON}` + `--no-nil-check` | SIGSEGV — flag wins |
| call on nil, `uses SysUtils` + `try..except` | `caught: EAccessViolation: Access violation (nil reference)`, continues, exit 0 |
| `p^` in `try..except`, default | SIGSEGV, `except` never runs |
| same, `{$NILCHECKS ON}` | `caught: EAccessViolation`, continues, exit 0 |
| the page's own snippet, extracted from the Markdown | both halves as documented |
| the two quoted diagnostics | string-compared to real output — exact |
