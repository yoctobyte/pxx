---
track: N
prio: 40
type: bug
---

# NilPy: uforth exceptiontest source-unlink test fails under the full driver

## Symptom

Running the Forth-2012 exception set under the standard 5-file driver
(prelimtest + tester + utilities + errorreport + exceptiontest), our
compiled uforth emits one extra failure CPython does not:

```
WRONG NUMBER OF RESULTS: 333 $$QWEQWEQWERT$$ 334^@13 3 }T   \ Test unlinking of sources
```

(the `^@` is a NUL byte in the payload). Everything else in the set is
byte-identical.

## Attribution

NOT from the 2026-07-22 session: reproduced identically with compilers
built from fe14f188 (session start), from HEAD, and with the
exception-message-text change — all three produce the same extra line.
Session 5i's "exceptiontest passes" was under different driver/state
(likely without the full 5-file preamble or with different leftover
S"-buffer state).

## Repro

```
cd ~/projects/uforth/tests
printf 'S" _drv_x.fth" INCLUDED\nBYE\n' | ./uforth   # _drv_x = 5-file driver ending in exceptiontest.fth
```
Diff against `python3 ../uforth.py` with the same stdin. The failing test
sits near exceptiontest's "Test unlinking of sources" (CATCH across an
INCLUDED file boundary — source stack unlink during THROW). Suspect area:
uforth's InputSource stack restore interacting with a NilPy gap
(exception unwind across the interpret_include recursion, or the
S"/counted-string circular buffer state), not the THROW/CATCH core (all
other exception tests pass byte-identical).
