---
track: N
prio: 35
type: bug
summary: "uforth's LAST suite diff (10/11 identical): `INCLUDE <bare-name>` uses the FIRST of uforth's two same-named `w_include` nested defs, not the later redefinition — and `1+` is undefined inside an INCLUDEd helper. Isolated repros of both shapes PASS."
status: done
---

# uforth's FILE word set: the wrong `INCLUDE`, and a word missing in an included file

`tests/_drv_file.fth` is the only file left differing in uforth's driver suite
(the other 10 are byte-identical). Both sides fail — at different points, for
different reasons:

```
cpython: ...ERROR: filetest.fth:278: THROW -13 (line: '0 SI_INC !')
pxx:     ...ERROR: filetest.fth:217: INCLUDE expects a string filename on stack
                                     (line: '  INCLUDE required-helper1.fth')
```

## Finding 1: the later `INCLUDE` redefinition does not win

uforth defines `w_include` TWICE, as two nested defs in two different enclosing
functions:

* uforth.py:1707 — pops a string, else raises *"INCLUDE expects a string
  filename on stack"*; registered `vm.define_word("INCLUDE", native=w_include)`;
* uforth.py:3041 — handles the stack form AND the ANS bare-name form via
  `vm.next_token_strict()`; registered later, with `immediate=True`.

pxx's error text is the FIRST one's, so the later registration did not replace
it. CPython uses the second (it reads the bare name and includes the file).

## Finding 2: `1+` is undefined inside an INCLUDEd file

Reached via the stack form, which both sides accept:

```
REQUIRE required-helper1.fth       pxx: THROW -13 at helper:3 ('1+')
S" required-helper1.fth" REQUIRED  cpython: Stack underflow at helper:3
```

CPython finds `1+` and fails on the empty stack (which is the test's business);
pxx cannot find the word at all. `5 1+ .` works fine at the REPL, so the
dictionary lookup is failing only in the nested-inclusion context.

## Isolated repros PASS — do not start from them

Both shapes were reduced and both match CPython:

* two same-named nested defs in two enclosing functions, registered into a dict
  under one key, second one winning — including with the `native=`/`immediate=`
  KEYWORD form and a `@dataclass` Word, i.e. uforth's exact spelling;
* `1+`-style digit-leading word names, defined and called.

So the cause needs uforth's real state. Suggested route, given hand-instrumenting
uforth produces a pxx binary that hangs (see
[[bug-nilpy-uforth-dot-paren-prints-nothing]]): uforth's own `--trace`, diffed
between the two runs, which is what cracked the `.(` case — look for the
`trace:call enter word=INCLUDE` line and what body it names, and for how
`required-helper1.fth`'s source frame differs.

## Gate

`tests/_drv_file.fth` byte-identical to the CPython run, the other 10 still
identical, `make test-uforth` still PASS, plus the per-fix loop.

## Log
- 2026-08-08 — resolved, commit 383f9c2f5.
