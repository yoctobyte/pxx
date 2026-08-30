---
track: N
prio: 55
type: bug
blocked-by: []
summary: "songformatter's render_backend.py (413 lines) does not finish compiling: killed at 25:00.06 wall clock, 95% CPU, RSS FLAT at 102 MB, state R — spinning, not allocating. The 2026-07-31 record says it compiled. Bounded rather than diagnosed: lines 1..296 compile in 7s, the whole file spins. Filed with no proposed cause because every cause tried so far has been wrong, and each wrong one is recorded so nobody re-walks it."
status: working
owner: frankwasm
---

# `render_backend.py` does not finish compiling

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

So the cycle alone is not sufficient. What `_text` has that my reproduction did
not: `self._y(y) + self._descent(font)`, `text.split(" ")`, `len(words) < 2`,
`pdf_string_width(...) is None`, `... or 0.0`, and `self.cv.create_text(...)`
into a Tk shim. One of those closes the loop.

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
