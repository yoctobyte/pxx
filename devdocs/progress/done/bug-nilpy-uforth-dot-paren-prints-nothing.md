---
track: N
prio: 40
type: bug
summary: "RESOLVED — `.(` printed nothing because next_token()'s None came back as the TEXT 'None', so its `if tok is None: break` could never fire. uforth's driver suite is now 10/11 identical to CPython; only the FILE word set differs."
status: done
---

# `.(` prints nothing — uforth's driver suite, 8 of 11 identical

Measured with the correct invocation (`"<file>" INCLUDE`, see
[[bug-nilpy-uforth-rc4-corpus-stack-underflow]] for why that matters), comparing
pxx's binary against CPython running the same `uforth.py`:

```
tests/_drv_c.fth       IDENTICAL       testje.for        IDENTICAL
tests/_drv_file0.fth   IDENTICAL       testjefixed.for   IDENTICAL
tests/_drv_locals.fth  IDENTICAL       testjefix2.for    IDENTICAL
tests/_drv_t.fth       IDENTICAL       testjefix3.for    IDENTICAL
tests/_drv_string.fth  DIFF            tests/_drv_x.fth  DIFF
tests/_drv_file.fth    DIFF
```

(It was 2/11 before the repeat-count and closure-row fixes of 2026-08-08.)

## NARROWED 2026-08-08: two of the three are the word `.(`

Not a trailing-newline problem — that was checked and ruled out (a file whose
last line has no newline INCLUDEs identically on both sides). The missing text
is the last line's OUTPUT, and that line is `CR .( End of String word tests) CR`.

Reduced to one word, at the REPL, no files involved:

```
CR .( hello) CR      CPython: "hello) CR"      pxx: nothing at all
.( hello)            CPython: "hello)"         pxx: nothing at all
```

No error, no diagnostic — `.(` runs and emits an empty string. (CPython
including the `)` in its output is uforth's own quirk; both sides must agree on
it either way.)

`w_dot_paren` (uforth.py ~3263) does four things, and EACH of them was probed in
isolation against the CPython oracle and PASSES:

* `int.from_bytes(vm2.memory[a:b], 'little', signed=True)` on a bytearray field
  through a dynamically-typed receiver — ok;
* `vm2.input_line[pos:]` — a str field read through the same — ok;
* `.find(')')` and the `[:end_idx]` slice — ok;
* `print(content, end='', flush=True)` — ok.

So the fault needs uforth's real state, not the shapes. The obvious next step —
instrumenting `w_dot_paren` — is BLOCKED by a second finding, below.

### Instrumenting uforth makes the pxx build HANG

Adding a `print(...)` inside `w_dot_paren`, or appending to a debug list field,
produces a binary that times out at startup (>60 s, no output) while the
uninstrumented build of the same file runs fine and CPython runs the
instrumented file fine. That is a lead in its own right and probably a separate
bug; it also means the usual print-probe is unavailable here. Reach for the
`.map` + gdb route instead, or bisect uforth's own startup.

## Superseded: the last-line theory

(Original framing, kept for the record.) `_drv_string` and `_drv_x` produce
every line CPython does except the **final** one:

```
 Test utilities loaded
 **********
-End of String word tests) CR          <- pxx stops here
```

This read as a dropped trailing line; it is not. See the narrowing above.

## The third is the FILE word set

`_drv_file` diverges earlier than CPython's own failure and for a different
reason — both sides fail, at different points:

```
cpython: ...******************ERROR: filetest.fth:278: THROW -13 (line: '0 SI_INC !')
pxx:     ...*************ERROR: filetest.fth:217: INCLUDE expects a string filename
                                on stack (line: '  INCLUDE required-helper1.fth')
```

Note pxx's message is about `INCLUDE required-helper1.fth` — the BARE-word form,
which the ANS test file uses and which uforth's own `INCLUDE` does not
implement (it pops a string). CPython gets past line 217, so uforth must have a
route that handles it there and pxx does not reach. Establish what CPython
actually does with that line BEFORE assuming a compiler bug — this exact form is
what produced a withdrawn ticket already.

## Gate

All 11 byte-identical to the CPython run, `make test-uforth` still PASS, plus
the per-fix loop. Worth splitting once the last-line cause is known: it is
plainly one bug, and the FILE word set is plainly another.



## ROOT CAUSE 2026-08-08 — and a RETRACTION

**Retracted first:** I recorded a root cause of "NilPy strings are byte strings,
so uforth's byte offset into a str lands past the end". That was WRONG. The
disproof was already in my own measurements before I wrote it: `.( abc)` is pure
ASCII on every path and failed identically. I had taken a real but unrelated
`len=53` vs `len=67` divergence, seen on a COMMENT line during startup, and
attached it to a failure it does not explain.

### The actual cause

`.(` is not the `w_dot_paren` native at all — EXTRA.UFO REDEFINES it as a Forth
word with a PYTHON body:

```python
while True:
    tok = vm.next_token()
    if tok is None:
        break
    ...
```

`next_token()` is `-> Optional[str]`, and `return None` from a str-returning def
handed back the TEXT 'None'. So `tok is None` was always False and the loop's
only exit could never fire: it ran to the end of the line and then appended the
string 'None' forever. Hence "prints nothing" for `.(` and a HANG for an
isolated copy of the same body — the same bug, two faces.

Fixed in [[bug-nilpy-return-none-from-a-str-returning-def-yields-the-text-None]].

### How it was actually found

uforth's OWN `--trace`, diffed between the two runs, which sidestepped the
instrumented-build hang noted above:

```
cpython: [00027] .(:0 PyInline(src="... while True: tok = vm.next_token() ...")
pxx    : [00027] .(:0
```

— the trace named the word's body, which is what revealed `.(` was a PYTHON
word rather than the native I had been reading.

### Result

uforth's driver suite: **10 of 11 byte-identical** to CPython (2/11 at the start
of this arc, 8/11 before this fix). Only `tests/_drv_file.fth` differs, on the
FILE word set — described above and still open.

## Log
- 2026-08-08 — resolved, commit PENDING-COMMIT.
