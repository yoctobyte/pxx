---
track: B
prio: 45
type: feature
blocked-by: []
summary: "CORRECTED 2026-08-29 by the lane that filed it: the facade is NOT missing the two-tuple pad. padx/pady are already Variant, the braced pair is already emitted, and `grid info` on a live widget reports `-padx {8 6}`. The call is rejected by bug-n-a-methods-keyword-call-drops-a-tuple-argument-when-an-earlier-default-is-skipped — a METHOD call with an earlier default left unbound and an object-valued Variant. Nothing to change in lib/pcl; kept open only to track the app-side consequence."
status: unfinished
owner: frank-b
---

# tkinter facade: `grid(padx=(8, 6))` — the two-tuple pad

- **Type:** feature (library surface, tkinter facade) — **Track B**.
- **Filed:** 2026-08-29 by the wasm lane against pin v392 (`60b060bb54a8`).


> ## CORRECTION 2026-08-29 — the diagnosis below is WRONG, the measurement is not
>
> Written by the wasm lane, which filed this ticket and got its cause wrong.
> frankB investigated and **changed nothing in `lib/pcl`**, which is the right
> outcome and the one this ticket as written would have prevented.
>
> **The facade was already complete.** `lib/pcl/tkinter.pas:104` declares
> `const padx: Variant = 0`, and line 106 carries the comment *"padx/pady are
> VARIANT: tkinter takes either a number or a (left, right)"* — the exact
> semantics the "Fix" section below proposes adding. frankB confirmed the
> emitter too, by asking **Tk itself** rather than our own formatter: `grid
> info` on a live widget reports `-padx {8 6}`.
>
> **The real cause** is
> [[bug-n-a-methods-keyword-call-drops-a-tuple-argument-when-an-earlier-default-is-skipped]]:
>
> ```python
> c = v6.TC(a=0, v=(8, 6))     # OK    — constructor
> c.meth(a=0, v=(8, 6))        # FAILS — method
> ```
>
> A **method** call, an **earlier default left unbound**, and an
> **object-valued Variant** are all three required. So this was never about
> tuples, and it explains the table below exactly: `padx=8` works because
> scalars are unaffected; `padx=(8, 6)` fails because `sticky`, `columnspan`
> and `rowspan` were skipped ahead of it. Re-verified here — the app's spelling
> fails, `grid(row=0, column=0, sticky="e", columnspan=1, rowspan=1,
> padx=(8, 6), pady=2)` compiles, and `grid(padx=(8, 6))` **alone** also fails,
> which the tuple theory cannot explain and the skipped-default one predicts.
>
> **How I got it wrong, since I had written the rule three times the same
> evening.** `no overload of grid matches these arguments` plus "scalar works,
> tuple fails" reads as *the tuple form is unimplemented* — and that reading is
> available without opening a single file. I never opened `tkinter.pas`. This
> is the ticket I closed hours earlier saying *a diagnostic that names a cause
> may be naming the discriminator*, and the cost of checking was one grep. I
> skipped it because the story was coherent, and a coherent story is precisely
> the input that makes verification feel unnecessary.
>
> Operational form, because "verify your claims" is too weak to act on: **a
> ticket that proposes a fix must QUOTE the code it proposes to change** — not
> cite it, quote it. I could not have written "padx must become Variant"
> underneath a line reading `const padx: Variant = 0`.
>
> **The one-line workaround is deliberately NOT taken.** Naming every option is
> legitimate and is not a compiler-appeasement reshape — nothing is renamed or
> rerouted, the app just spells out options it already sets. It is still an
> **app-source edit**, and this track's principal goal is that songformatter's
> source stays unmodified CPython, to the point that the single app-side change
> that does exist (the fallback import) is scheduled for removal once dotted
> imports land. Spending the principal goal to save one N ticket is the wrong
> trade from here. `settings.py` stays as CPython wrote it and waits on the N
> fix. If the owner wants the app moving tonight at that price, the spelling is
> in the paragraph above and it works.
>
> Everything below is the original filing, left intact. The measurement table
> is sound; the "Fix" section is the part that was invented.


## Repro

```python
import tkinter as tk
root = tk.Tk()
lbl = tk.Label(root, text="x")
lbl.grid(row=0, column=0, padx=(8, 6), pady=2)
```
```
pascal26:4: error: no overload of grid matches these arguments
```

| call | result |
| --- | --- |
| `grid(row=0, column=0)` | ok |
| `grid(..., padx=8, pady=2)` | ok |
| `grid(..., sticky="e", padx=8, pady=2)` | ok |
| `grid(..., padx=(8, 6), pady=2)` | **fails** |

So the whole option surface is fine and it is specifically the tuple form.

## What tkinter means by it

`padx`/`pady` take either a scalar (that much padding on both sides) or a
2-sequence `(before, after)` — left/right for `padx`, top/bottom for `pady`. Tcl
receives it as a two-element list, so the facade needs to emit `-padx {8 6}`
rather than a single number. `pack` takes the same forms and should get the same
treatment in the same pass; `place` does not have these options.

Note the brace-quoting half is already understood here: a multi-word option
value reaching Tk unbraced was the `-scrollregion 0 0 500 1026` bug fixed during
pass seven of [[feature-demo-songformatter-pxx-target]], where three of the four
numbers arrived as stray arguments. Same shape, so the same escaping applies.

## Why it is worth doing now

`settings.py:183` is the only remaining wall in that module —
`label.grid(row=row, column=0, sticky="e", padx=(8, 6), pady=2)` — and
settings.py otherwise compiles and runs, building all 60 of its widgets. This is
the last thing between it and a clean build.

## Gate

Track B's: `make lib-test` / `make demos` green, built with `$(PXX_STABLE)`
(never rebuild the compiler), plus the repro above compiling and the padding
actually applied asymmetrically on screen — a scalar fallback that silently
ignores the second element would pass a compile check and is the wrong fix.


## Triage (frank-b, 2026-08-29) — NOT a Track B defect; blocked on Track N

**The facade is already complete.** `padx`/`pady` on both `grid` and `pack` are
already `Variant`, and `TkiOptPad` already renders the `(before, after)` pair as
Tk's braced list. Nothing in `lib/pcl/tkinter.pas` needed changing, and I
changed nothing.

The gate's own requirement — *"the padding actually applied asymmetrically ...
a scalar fallback that silently ignores the second element would pass a compile
check and is the wrong fix"* — is met today. Verified by asking **Tk**, not our
own formatter (`grid info` on the live widgets under xvfb):

```
pair  : ... -padx {8 6} -pady 2 -sticky e
scalar: ... -padx 8 -pady 2 -sticky e
pady  : ... -padx 1 -pady {3 9} -sticky e
```

**What actually rejects the call is a NilPy argument-binding bug**, filed as
[[bug-n-a-methods-keyword-call-drops-a-tuple-argument-when-an-earlier-default-is-skipped]].
A keyword call to a **method** that leaves an earlier defaulted parameter
unbound rejects an object-valued Variant argument. The same signature and the
same call bind correctly through the **instantiation** path and through a
unit-level procedure — same class, only the path differs:

```python
c = v6.TC(a=0, v=(8, 6))     # OK
c.meth(a=0, v=(8, 6))        # no overload of meth matches these arguments
```

Which is why the ticket's own table reads the way it does: `grid(..., padx=8)`
works because a scalar is not affected, and `grid(..., padx=(8, 6))` fails
because three options before it were left unbound. Supply them all and the
tuple form compiles and works **today**:

```python
lbl.grid(row=0, column=0, sticky="e", columnspan=1, rowspan=1, padx=(8, 6), pady=2)
```

That is the **workaround available now** for `settings.py:183` if the wasm lane
does not want to wait for the N fix — it is one line and it is not a
compiler-appeasement reshape of library code, it is an application spelling
every option it is already setting.

**Why this ticket stays open rather than being resolved:** its ask is that the
short spelling work, and it does not. But there is nothing left for Track B to
do, so it is parked on the N bug rather than held in `working/`.

---

## Re-verified 2026-08-30 (frankB) — the blocker is closed and this still fails, for a reason that is not a defect

[[bug-n-a-methods-keyword-call-drops-a-tuple-argument-when-an-earlier-default-is-skipped]]
resolved earlier today. `tools/progress.sh check` then flagged this ticket as a
STALE-EDGE: sitting in `blocked/` with every blocker closed, which makes it
invisible to `ready`/`next` forever. Re-measured before moving it, and the
answer is neither "fixed" nor "still broken":

**The fix is not in the pin, and Track B builds only with the pin.** Pin is
**v393** (`1d69760deabe`, blessed 2026-08-29 20:28 at `1fb9774b7417`); the N fix
landed on master on 2026-08-30, *after* it. `compiler/pascal26` in this tree is
byte-identical to `pinned`, so there is no binary here that carries the fix and
this lane does not build one.

Measured through v393 — the boundary is unchanged and exactly as the correction
above describes:

```
grid(row=0, column=0, sticky="", columnspan=-1, rowspan=-1, padx=(8, 6), pady=2)   COMPILES
grid(row=0, column=0, padx=8)                                                      COMPILES
grid(row=0, column=0, padx=(8, 6))                                                 FAILS
grid(padx=(8, 6))                                                                  FAILS
```

A NilPy-defined class with the same *shape* (`c.meth(a=0, v=(8, 6))` with an
earlier default skipped) **passes** through v393. That is not evidence the fix
arrived — it is the control that confirms the resolution's own diagnosis: the
refusal comes from `FindUMethOverloadAhead`, the speculative overload probe,
which a **Pascal-declared façade method** goes through and a NilPy class method
does not. Two paths, one shape; only the façade arm is affected, and only the
façade arm is what tkinter is.

**So the gate is now pin advancement, not a ticket.** `blocked-by` is emptied
because it named a closed ticket, and the ticket moves to `unfinished/` rather
than `backlog/` — putting it in the ranker would dispatch work that cannot be
done from this lane until the next `make pin` picks up the N fix.

**To retire it:** after the next pin, re-run the four spellings above. If rows 3
and 4 compile, close it — `lib/pcl` needs no change, which was this ticket's
finding all along. If they still fail, that is a *new* N/A finding against a pin
that contains the fix, and it should be filed as one rather than reopened here.

## Retirement test WIDENED 2026-08-30 — `grid` is one of four, not one

Re-checked at HEAD: the pin is still **v393** (`1d69760deabe`), unchanged, so
the four spellings above still behave exactly as recorded and the ticket is
still gated on pin advancement. Nothing to build. But the retirement test as
written checks **one method**, and that is too narrow — for the same reason two
other tickets went wrong tonight: an acceptance aimed at the reported symptom
leaves the siblings unverified.

The N fix ([[bug-n-a-methods-keyword-call-drops-a-tuple-argument-when-an-earlier-default-is-skipped]],
`51b0753e7`) is general — `OverloadArgParamIdx` resolves an argument to its
declared parameter in `FindUMethOverloadAhead`, and its commit message states
that `settings.py` compiles at lines 178 and 183. So `grid` will pass. The
question the four spellings cannot answer is whether the **rest of the façade**
passes with it.

### The at-risk shape, enumerated over `lib/pcl/*.pas`

A façade **method** is exposed when a `Variant` parameter can be reached with an
earlier defaulted parameter left unbound. Eight declarations match; two are
**unit-level functions**, which the parent ticket's own boundary table says take
a different path (no probe), and they are confirmed unaffected below. That
leaves six methods, four of which have a call a real application would write:

| method | the exposed parameter | today, at v393 |
| --- | --- | --- |
| `Widget.grid` | `padx` / `pady` | **FAILS** |
| `Widget.pack` | `padx` / `pady` | **FAILS** |
| `Canvas.configure` / `.config` | `scrollregion`, `yscrollcommand` | **FAILS** |
| `Canvas.create_text` | `font` | **FAILS** |
| `Text.tag_configure` | `underline` | shape present; a tuple `underline` is not a call anyone writes, so untested |
| `askopenfilename` / `asksaveasfilename` | `filetypes` | **compiles** — unit-level function, not a method |

Measured now, so the post-pin check has a baseline rather than a guess:

```
pack(padx=(8, 6))                                   FAILS: no overload of pack
pack(side="left", fill="x", expand=0, padx=(8, 6))  COMPILES
configure(scrollregion=(0, 0, 100, 100))            FAILS: no overload of configure
configure(state="normal", scrollregion=(0,0,1,1))   COMPILES
create_text(1.0, 2.0, "hi", font=("Arial", 12))     FAILS: no overload of create_text
create_text(..., anchor="w", fill="red", font=...)  COMPILES
askopenfilename(filetypes=[("a", "*.b")])           COMPILES   <- the control
```

Each failing row has its own passing row directly underneath, differing only in
whether the earlier defaults are named. Same diagnostic, same signature, same
mechanism. And `askopenfilename` is the control that keeps the claim honest: it
has the identical parameter shape and an object-valued argument, and it compiles
today — because it is not a method, exactly as the parent ticket predicted.

### To retire this ticket

After the next pin, re-run **all seven rows** above plus the original four
`grid` spellings. If every FAILS row flips to COMPILES and the two COMPILES
controls stay green, close it — `lib/pcl` needs no change, which was this
ticket's finding all along. If any FAILS row survives, that is a residue of
`51b0753e7` in a sibling it did not reach, and it is a **new N ticket** with
this table as its boundary — not a reopen of this one.

Still in `unfinished/` and still owned by this lane: it cannot be completed from
Track B until the pin carries the fix, and claiming it into `working/` would be
a lock over work that cannot proceed.

### Pre-answered at HEAD, 2026-08-30 — every row flips, but the pin has NOT moved

The retirement run above was executed early, against a compiler built from
source at HEAD rather than against `$(PXX_STABLE)`. **This does not retire the
ticket** — Track B ships against the pin, the pin is still **v393**
(`1d69760deabe2865`), and nothing in `lib/pcl` changes either way. It answers
the one question the wait was hiding: *will the post-pin check close this
cleanly, or fragment into an N ticket?* Cleanly.

Provenance of the binary under test, because a verification build that silently
no-ops is the failure mode here:

```
worktree at HEAD d9b663137, seed = stable_linux_amd64/default/stable_pinned
converged after 2 round(s)
self-host fixedpoint: verified — 2 round(s), 837193ea839c
```

Built sha `837193ea839c` differs from the seed `1d69760deabe`, and `converged`
was printed — so the compiler under test is genuinely HEAD's, not the pin's
wearing a new mtime.

All eleven rows — the seven above plus the original four `grid` spellings:

```
grid(row=0, column=0, padx=(8, 6), pady=2)            COMPILES
grid(padx=(8, 6))                                     COMPILES   <- was FAILS
pack(padx=(8, 6))                                     COMPILES   <- was FAILS
pack(side="left", fill="x", expand=0, padx=(8, 6))    COMPILES
configure(scrollregion=(0, 0, 100, 100))              COMPILES   <- was FAILS
configure(state="normal", scrollregion=(0,0,1,1))     COMPILES
create_text(1.0, 2.0, "hi", font=("Arial", 12))       COMPILES   <- was FAILS
create_text(..., anchor="w", fill="red", font=...)    COMPILES
askopenfilename(filetypes=[("a", "*.b")])             COMPILES
```

Nine of nine green is exactly the shape that should be distrusted, because a
compiler that accepted *everything* would produce the same table. Controls, on
the same binary:

```
grid(nosuchkeyword=(8, 6))   REJECTED: Widget.grid has no parameter named 'nosuchkeyword'
lbl.no_such_method(...)      REJECTED: Label has no method no_such_method
grid(row=0, column=0, padx=(8, 6), pady=2)   binary built, runs, prints "grid-pad ok"
```

Rejection is still real and still specific to the right thing, and the accepted
row does not merely typecheck — it links and runs. So `51b0753e7` reached all
four façade methods, not just `grid`; there is no sibling residue and no new N
ticket to file.

**What is left is purely the pin.** When the pin moves past `51b0753e7`, re-run
the eleven rows against `$(PXX_STABLE)` and close this — the answer is already
known, but the ticket's gate is the *stable* compiler, and a pre-answer at HEAD
is not that. Until then it stays in `unfinished/`.
