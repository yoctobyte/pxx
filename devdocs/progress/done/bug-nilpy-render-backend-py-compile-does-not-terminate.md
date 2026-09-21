---
track: N
prio: 55
type: bug
blocked-by: []
summary: "FIXED -- RE-MEASURED 2026-09-21 AND IT COMPILES IN 8.7 SECONDS, against the original `timeout 1500` expiring at 25:00 wall / 95% CPU / RSS flat 7,616 kB on pin v392. THE SUBJECT IS `render_backend.py` AND ONLY THAT -- three programs share the songformatter name and disagree (SongFormatter.py the Tkinter GUI; render_backend.py this one; key_analysis.py the one the matrix records GREEN off an untracked keydemo.py), so a row that does not name the file is worth nothing. rc=0 on BOTH pin v414 (sha256 aeadb1754b80b622, 8.71s, 99% CPU, 120,804 kB) and HEAD b48a5ce0d (binary 5c8c3b8a4c051337, 8.51s), producing BYTE-IDENTICAL 2,915,104-byte artefacts that run and exit 0 with no output -- correct, since the file is 9 classes/functions with no `__main__`. Control rows on a trivial NilPy file passed on both binaries first, because a broken harness makes every row time out and reads exactly like this bug. AND THE SOURCE DID NOT MOVE, which is where a re-measure lies: render_backend.py was last touched `0d7a5c2` 2026-07-26, a MONTH BEFORE this was filed, and `_text` is still at line 244, the exact line this ticket named as the spin entry. Same program, different compiler. FIXED AT OR BEFORE v414 and the window is NOT narrowed further -- it already compiles under the PIN, and narrowing is a bisect the owner deprioritised (*\"for this moment, not important\"*). v414 closed lekkerzeilen blockers 03 and 04, both the shape that produces a non-terminating compile, recorded as CANDIDATES and not as the cause: nothing here tested it and this ticket already carries seven disproved suspects. RESIDUAL AND EXPLICITLY NOT CLOSED BY THIS: both compilers still warn at `render_backend.py:115` that no class declares `.getRGBData()` so it dispatches on the receiver at run time -- the image-surface family the close-out records at :114. This ticket was a compile that never terminates; the runtime image surface is a separate question."
status: done
owner: ""
---

# `render_backend.py` does not finish compiling

> **"It hangs" and "it loops forever after a known point emitting nothing" are
> different tickets, and only the second one tells you where to put a
> breakpoint.** This ticket is the second. The proof, the freeze point, and —
> most usefully — the seven shapes already DISPROVED are in "Update 3" and its
> follow-up near the bottom; read those before reproducing anything.
>
> Parked by frankwasm 2026-08-30, deliberately and not for lack of leads: the
> one remaining suspect is keyword-call-into-shim resolution, which is adjacent
> to that session's own `pasparser_call.inc` work, making it the least neutral
> reader of it.

- **Type:** bug (compiler non-termination) — **Track N** by the file's language;
  re-lane to A if the loop turns out to be below the frontend.
- **Filed:** 2026-08-29 by the wasm lane, against pin v392 (`60b060bb54a8`),
  while re-measuring [[feature-demo-songformatter-pxx-target]].
- The 2026-07-28 and 07-31 passes both record this module compiling, so this is
  a regression rather than a gap. The app has not changed (`~/songformatter`
  HEAD is still `12cf40e`, 2026-07-28).

## Measurement

```
$ cd ~/songformatter
$ /usr/bin/time -v timeout 1500 pascal26 render_backend.py /tmp/rb
Command exited with non-zero status 124
        Elapsed (wall clock) time: 25:00.06
        Maximum resident set size (kbytes): 102252
```

Sampled while running: **95% CPU, state R, RSS flat at 102252 KB** across 20
seconds. So it is **spinning, not allocating** — an unbounded or pathological
loop, not a memory blowup. That distinction is the one thing here established
rather than guessed, and it says the fix is a loop bound, not a capacity.

No stack sample: `ptrace_scope` blocks attaching to a running process on this
box, and re-running under gdb costs another 25 minutes per attempt.

## Bound

| input | result |
| --- | --- |
| lines 1..140 (through `_apply_color_key`) | ok, 7s |
| lines 1..184 (through `_map_font`) | ok, 8s |
| lines 1..296 (into `class TkCanvasBackend`) | **ok, 7s** |
| lines 1..378 | fails fast: `undefined variable (_TkTextObject)` at :301 |
| the whole file | **spins** |

So the loop needs something at or after line 297, and the 1..378 row cannot
narrow it because the forward reference at :301 aborts the compile before the
loop is reached.

## Causes tried and REJECTED, so nobody re-walks them

Each of these looked right and is wrong:

* **Not the `_as_tk_photo` helper.** Deleting it made the compile finish in 9
  seconds, which I read as a fix. It is not: the deletion makes compilation
  **fail earlier**, at the call site on line 329, so it never reaches the loop.
  A fast failure masking a slow one reads exactly like a repair. Replacing the
  function with a `return None` stub — which keeps the call site valid — still
  spins.
* **Not a forward class reference.** `TkCanvasBackend.beginText` returns a
  `_TkTextObject` defined 80 lines later. Moving `_TkTextObject` above
  `TkCanvasBackend` still spins.
* **Not the construction itself.** Replacing `return _TkTextObject(self, x, y)`
  with `return None` still spins.
* **Not mutual class reference on its own.** Two classes that construct and
  store each other compile in 3 seconds.

## The probe trap that cost an hour, and the rule that follows

**Any bisect of this file must run in `~/songformatter`.** The identical bytes,
compiled from a scratch directory, fail in 7 seconds with

```
pascal26:1: error: unexpected token
```

which reads as a parse bug at line 1 and is actually an unresolvable sibling
import reported at the wrong line. `cmp` confirms the two inputs are
byte-identical; only the working directory differs. Every truncation test run
outside the app directory measured import resolution rather than the loop, and
they all "failed" identically, which looked like a consistent finding.

Two probe artefacts, one lesson: **a probe that changes the failure has not
necessarily reached the defect.** A faster failure and a different failure are
both indistinguishable from progress unless you check *which* failure you now
have.

## Why no proposed cause

Every cause proposed for this so far has been wrong, and the ones above were
each supported by a passing experiment. Filing the bound and the timing is
worth more than a fifth guess. Whoever picks it up starts from: something at or
after line 297, in a build that reaches line 378 without aborting.

## Gate

Track N's: `make test-nilpy` green + self-host byte-identical, plus
`render_backend.py` compiling from `~/songformatter` in bounded time — and the
timing recorded, since "it finished" is not a result here without a number next
to it.

---

## Update 2026-08-30 (frankwasm): it now FAILS as an import, and still hangs direct

With the str/helper collision fixed (`05eff4cc9`), `convertrawtext.py` and
`SongFormatter.py` get past `key_analysis.py` and reach this module. Pulled as
a UNIT it no longer hangs — it produces an error, at `render_backend.py:114`:

```
error: Nil Python: cannot unpack this value into several names
       — it is not a list, tuple or variant
  near:  img  getSize   >>>   Image
```

```python
w, h = img.getSize()
return Image.frombytes("RGB", (w, h), img.getRGBData())
```

Compiled **directly** it still does not terminate (timed out at 120s), so the
non-termination this ticket is about is unchanged. The two faces are worth
keeping apart: as an import it now gets far enough to type something and refuse,
which is a *diagnosable* state and a better starting point than the hang.

`getSize` is defined nowhere in the app — it is reportlab's `ImageReader`, so
`img` is a shim-typed value the compiler resolved to something concrete and
wrong. Note the refusal text: it accepts a **variant**, so an unknown type
would have been fine. Something typed it definitely, and incorrectly.

Probable sibling — check before treating this as its own animal:
[[bug-n-a-tuple-returning-str-method-prints-raw-memory-when-returned-from-a-def]]
is the same shape one family over (a METHOD result that should be a tuple and
is not typed as one). If both come from how a method's result type is inferred,
one fix closes both; if not, that is worth knowing early.

This is now the wall for [[feature-demo-songformatter-pxx-target]].

## Update 2: the getSize refusal is a LIBRARY bug, and it was hiding this one

Claimed by frankwasm 2026-08-30 (promoted to effective prio 68 once
[[feature-demo-songformatter-pxx-target]]'s `blocked-by` was corrected — it
listed three tickets that are all in `done/`, so this one never inherited its
68).

The `w, h = img.getSize()` refusal in Update 1 is **not a compiler defect and
not this ticket**. `lib/pcl/mimic_reportlab_lib_utils.pas` declares
`ImageReader.getSize: AnsiString` returning `''`, where reportlab returns a
`(width, height)` pair. The compiler is correct to refuse to unpack a string.
Filed as
[[bug-b-imagereader-getsize-returns-a-string-where-reportlab-returns-a-pair]]
(Track B, `lib/pcl`) — the shim's own subset policy says a narrowed feature
"fails loudly at drawImage", i.e. at RUN time; a wrong RESULT TYPE fails at
COMPILE time in the caller and takes the module with it.

**Measured, with that shim shape applied locally and then reverted:**

| shim | `convertrawtext.py` |
| --- | --- |
| `getSize: AnsiString` (today) | stops at `render_backend.py:114`, seconds |
| `getSize: TPyList` (a 2-element pair) | **no error; ran past 200s without finishing** |

So the string return was **masking this ticket, not causing it**. With the
library bug fixed the compile reaches the non-termination and stays there,
which is the first time the hang has been observed through the *import* path
rather than only on a direct compile. Direct compilation still does not
terminate either (timed out at 120s), unchanged.

That gives whoever takes this two doors into the same hang instead of one, and
the import door is the one that matters for the demo. It also means this ticket
cannot be closed by fixing the library: the two are independent and sequential.

**Not started beyond this.** The lane holds the ticket; the diagnosis above is
banked rather than half a fix, per `devdocs/dev/root-cause-over-microfix.md`.

## Update 3 (frankwasm, 2026-08-30): it IS an infinite loop, and it is in `_text`

### It is a loop, not slow — proved, not assumed

`PXXDBG=all`, same input, two horizons:

| run | output |
| --- | --- |
| `timeout 20` | 54,577 lines |
| `timeout 45` | 54,577 lines |

`cmp` says **byte-identical**. The compiler emits 54,577 debug lines, stops
emitting entirely, and then spins in a region that prints nothing. `VmRSS` is
**flat at 7,616 kB** across 20s of sampling, so it is a tight non-allocating
loop — not a runaway allocation and not a slow fixed point still making
progress. Either of those would have shown movement in one of the two
measurements; neither did.

That distinction is the whole reason to record this: "it hangs" and "it loops
forever emitting nothing after a known point" are different tickets, and only
the second one tells you where to put a breakpoint.

### Where it freezes

The last lines emitted, in order, are the parameter list of `_text`:

```
PXXDBG n.shadow x         nilpyuser=TRUE
PXXDBG n.shadow y         nilpyuser=TRUE
PXXDBG n.shadow text      nilpyuser=TRUE
PXXDBG n.shadow font      nilpyuser=TRUE
PXXDBG n.shadow pdf_font  nilpyuser=TRUE
PXXDBG n.shadow self      nilpyuser=TRUE      <- last line ever emitted
```

That is `def _text(self, x, y, text, font, pdf_font)` at `render_backend.py:244`.
The bisect agrees independently: deleting methods 297-378 still hangs, and no
truncation that stops before `_text` does.

`_text`'s first interesting statement is the shape to look at first:

```python
name, size_pt = pdf_font        # unpack of an UNANNOTATED parameter
```

and `pdf_font` arrives on a genuine cycle — `_TkTextObject._flush` unpacks a
list of tuples and feeds them straight back in:

```python
for (x, y, text, font, pdf_font) in self.lines:
    self.b._text(x, y, text, font, pdf_font)
```

so `_text`'s parameter type depends on `_flush`'s tuples, which depend on
`_TkTextObject.__init__`'s `backend._pdf_font`. A→B→A through tuple unpacking.

### Corroborating: 18x re-derivation before the freeze

Of the debug output, `a.opovl` (operator-overload resolution) is 34,970 lines.
**17,485 queries, 967 distinct** — the same `(op, left, right)` triple asked up
to 851 times. That is not itself the loop (the loop emits nothing), but it says
the same resolution is being re-derived rather than memoised, which is the kind
of pass that fails to reach a fixed point.

### NOT minimised — and here is what is already excluded

Recorded so the next attempt does not repeat mine. All of these compile fine:

- mutual `A <-> B` class references, plain
- `B` holds `A`, `A` calls back into `B` through a stored `backend`
- the full cycle shape: `A.flush` unpacking a list of tuples into `B._text`,
  with `B._text` unpacking one of its own parameters — **including** the
  `name, size = pdf_font` line, which was my main suspect
- module-constant default arguments (`def __init__(self, w=PAGE_W)`)
- class declaration ORDER (swapping `_TkTextObject` before `TkCanvasBackend`
  still hangs, so it is not a forward reference)
- comment removal (still hangs, so it is not raw token count)

So the cycle alone is not sufficient. I then added `_text`'s real ingredients
back one at a time onto that cycle, and these ALSO compile clean:

- `self._y(y) + self._descent(font)` on the first line
- `text.split(" ")` and `len(words) < 2`
- a module-level `pdf_string_width` with the real body — a function returning
  **None or a float** through two `try`/`except` arms — plus `... is None` and
  `... or 0.0` at the call sites

What is left, and what I could NOT get to reproduce standalone because it needs
a real Tk canvas to resolve against: `self.cv.create_text(x, py, text=text,
anchor="sw", fill=self._fill, font=font)` and `_descent`'s
`tkfont.Font(root=self.cv, font=font).metrics("descent")`. Both are **keyword
calls into a shim on an UNANNOTATED receiver** (`self.cv = tk_canvas`, a plain
constructor parameter), and `_descent` is called from `_text`'s first line. In
isolation they fail with `no class declares ...` rather than hanging, because
nothing types `self.cv`; in the real module the caller supplies one. That is
where I would start.

One hypothesis already **excluded**, so nobody re-runs it: "`_text` has two
callers with different argument types, so its parameter type oscillates."
`drawString` (line 297) is the second caller, and deleting the whole 297-378
range still hangs.

### A warning about bisecting this file

Truncating with `head -n` lands inside method bodies and docstrings and produces
**misleading errors** — including `undefined variable (PAGE_W)` at line 195 for a
constant plainly defined at line 52. Delete whole method blocks with `sed
'A,Bd'` instead. I lost time to that and the false error looks like a real
second bug.

### Attaching a debugger

`ptrace_scope` blocks `gdb -p` on this box. Run the compiler as gdb's CHILD
(`gdb --args`) instead; that works. `kill -INT` on a batch-mode gdb kills gdb
rather than interrupting the inferior, so send the signal to the inferior.

## RESOLVED BY RE-MEASUREMENT 2026-09-21 — IT COMPILES, AND THE SOURCE IS THE SAME SOURCE

Re-measured at frankuser's direction after 22 days and three pins. **Scope was
re-measure only; no bisect, on the owner's explicit deprioritisation.**

**THE SUBJECT IS `render_backend.py` AND NOTHING ELSE.** Three programs share
the songformatter name and they disagree — `SongFormatter.py` (Tkinter GUI),
`render_backend.py` (this ticket), and `key_analysis.py` (the one the matrix
records GREEN, driven by an untracked `keydemo.py`). *"songformatter works"*
and *"songformatter does not compile"* have both been true, about different
programs. Every row below names the file.

    row                          rc   wall     CPU   maxRSS
    CONTROL      / pin v414       0   0:02.82  96%    73,444 kB
    CONTROL      / HEAD           0   0:02.71  97%    74,088 kB
    render_backend.py / pin v414  0   0:08.71  99%   120,804 kB
    render_backend.py / HEAD      0   0:08.51  99%   121,444 kB

    pin v414 = sha256 aeadb1754b80b622
    HEAD     = b48a5ce0d, binary sha256 5c8c3b8a4c051337 (rebuilt, `converged`)

**Against the original: `timeout 1500` expired, 25:00 wall, 95% CPU, RSS flat
at 7,616 kB, on pin v392 (`60b060bb54a8`).** It now finishes in **8.7
seconds**.

**THE CONTROL ROWS ARE WHY THE SUBJECT ROWS MEAN ANYTHING.** A broken harness
or a broken binary makes every row time out and reads exactly like this bug. A
trivial three-line NilPy file compiled clean on both binaries first.

### The source did not change — checked, because this is where a re-measure lies

A "fixed" verdict is worthless if the program moved. `git log -- render_backend.py`
in `/home/neo/songformatter` shows its last touch as **`0d7a5c2`, 2026-07-26** —
**a month BEFORE this ticket was filed on 2026-08-29**, and nothing since.
`_text` is still at line 244, the exact line this ticket named as the spin's
entry. **Same program, different compiler, different outcome.**

### Fixed at or before v414 — and the window is NOT narrowed further, deliberately

It already compiles under the PIN, so the fix landed at or before v414 and is
not something in the last few commits. The ticket failed at v392. **That is the
honest window and narrowing it is a bisect**, which the owner deprioritised
(*"however, for this moment, not important"*). Not started.

v414 closed lekkerzeilen blockers 03 (a field shadows another class's method)
and 04 (a `@property` setter runs when the receiver has no slot) — both the
shape that produces a non-terminating compile — so they are the obvious
candidates. **Recorded as a candidate and NOT as the cause: nothing here tested
it, and this ticket has seven disproved suspects already.**

### Both compilers produce a byte-identical artefact, and it runs

2,915,104 bytes from each, `cmp`-clean. It executes and exits 0 with no output,
which is **correct** — `render_backend.py` has no `if __name__ == "__main__"`
block; it is 9 classes and functions, a module. Exit 0 with no output is what a
module with no entry point should do, and saying so matters because a silent
exit otherwise reads as a failure.

### Residual, NOT part of this ticket

Both compilers emit the same non-fatal warnings, unchanged between them:
`pascal26:79 pow` C-declaration disagreement on parameter 1, and
`pascal26:115` twice — *"no class declares a method or callable field
.getRGBData() — dispatching on the receiver at run time"*. The second is the
`getSize`/`getRGBData` image-surface family the close-out records at
`render_backend.py:114`. **This ticket was about a compile that never
terminates and that is closed; the runtime image surface is a separate
question and nobody should read this resolution as clearing it.**

### Owner's history, RELAYED and not verified here

Via frankuser: *"songformatter was one of the first python programs we tried.
we hacked some pdf rendering to mimic reportlab, so that's a regression."*
Recorded as his account, marked relayed, because it changes what a FAILURE
would have meant — a regression with a bisectable window rather than a missing
feature. **My rows do not bear on it either way**, since they found no failure
to attribute. The `mimic_reportlab_pdfbase_pdfmetrics` shim note in the output
above is consistent with it and is not evidence for it.

## Log
- 2026-09-21 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 45b413bab.
