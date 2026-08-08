---
track: N
prio: 40
type: bug
summary: "uforth's own driver suite is 8/11 identical to CPython. Two of the last three are ONE word: `.(` prints NOTHING under pxx. The third is the FILE word set. `make test-uforth` is GREEN; this is the layer past it."
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
