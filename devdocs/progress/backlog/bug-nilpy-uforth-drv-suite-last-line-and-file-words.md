---
track: N
prio: 40
type: bug
summary: "uforth's own driver suite is 8/11 identical to CPython. The last 3: two lose the FINAL line of an included file (no trailing newline), one diverges on the FILE word set. `make test-uforth` is GREEN; this is the layer past it."
---

# uforth's driver suite: 8 of 11 identical, 3 left

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

## Two of the three are ONE symptom: the last line is dropped

`_drv_string` and `_drv_x` produce every line CPython does except the **final**
one:

```
 Test utilities loaded
 **********
-End of String word tests) CR          <- pxx stops here
```

CPython's own output ends without a trailing newline ("\ No newline at end of
file" in the diff), and the missing text is the last line of the included `.fth`
— so the suspect is a file whose LAST LINE HAS NO TRAILING NEWLINE being dropped
somewhere between `pyopen` (which does append a trailing partial line) and
uforth's `interpret_file`. Reproduce directly: a two-line `.fth` whose second
line has no newline, INCLUDEd.

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
