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

## 2026-07-22 narrowing (fable-abcnp): repro reduced; NOT the finally machinery

Standalone repro (no 5-file driver needed):
```
: T7 S" 333 $$QWEQWEQWERT$$ 334" EVALUATE 335 ;
: T8 S" 222 T7 223" EVALUATE 224 ;
: T9 S" 111 112 T8 113" EVALUATE 114 ;
: C6 CATCH >R DROP DROP R> ;
6 7 ' T9 C6 . . . .
```
CPython: ForthThrow(-13) propagates, CATCH reports it. pxx: prints
`0 224 223 335` and the stack holds `... 222 333 0 334` — the undefined-word
ForthThrow(-13) is swallowed somewhere BELOW CATCH, a 0 lands on the stack
mid-line (some handler's success push), and interpretation RESUMES after the
bad token (334 gets pushed). So this is an exception-unwind swallow inside the
nested-EVALUATE interpret machinery, not an input-source restore bug per se.

Ruled out with NilPy probes (all CPython-identical): single and 3-deep nested
try/finally unwind; method-loop unwind through self-calls; except-arm
selectivity (except ValueError does NOT catch ForthThrow; the right arm
matches). So the swallow needs something in uforth's real call chain —
suspects: exec'd PYTHON-word boundary (pyeval frames during unwind), the
closure-captured get_in_pos/set_in_pos nested defs, or an except arm reached
through the xt/EXECUTE dispatch path.

Debugging note: enabling uforth's TRACE under pxx malfunctions on its own —
`if self.trace_filter and ...` with trace_filter=None filters pseudo-randomly
(None-variant truthiness / .upper() on a None field?), so the trace harness
can't be used as-is to bisect; that misbehaviour is itself a lead
(None-holding field truthiness in a compiled method).
