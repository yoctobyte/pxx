---
track: A+N
prio: 60
type: bug
status: open
found: 2026-09-20
found-by: frankS
blocked-by: []
summary: "MEASURED, not estimated: after `--dce`, compiler/builtin/pyeval.pas is 624,684 B of a riscv32 ESP image's 2,074,812 (30.1%) and 681,868 B of xtensa's 1,736,175 (39.3%), for a program that never calls eval() or exec(). pyeval is a runtime tree-walking interpreter written for uforth's PYTHON-bodied words, and its own header says `NOT auto-used by NilPy yet`. Its single largest routine, PyHostCall, is 109,396 B by itself -- 5.3% of the whole image in one body. DCE drops only 13.7% of the unit (723,548 -> 624,684) against 30.7% of the image overall, so something ROOTS most of it rather than calling it: the suspects are the @proc / VMT / RTTI root classes (an address in a table is reachable from anywhere by construction) and pylib's hook variables that pyeval installs into. The mechanism to establish is WHICH root keeps each body alive; the instrument for that does not exist yet -- --dce-report says which bodies died, never why one lived. Rung of umbrella-an-esp32-image-is-as-small-as-it-can-be: it is the single largest identified component of an ESP NilPy image after DCE."
---

# A static NilPy program links the runtime's eval() interpreter

## The measurement

Program: `examples/esp32/nilpy-c3/main/main.npy` (a class, a list, a loop,
`print` -- no `eval`, no `exec`, no `compile`). Compiler `74ff679403b8`,
`--platform=esp --no-signals`, `--dce` on. Live code attributed to source unit
by matching each sized symbol in the object against the routine declarations in
`compiler/builtin/*.pas`, `lib/rtl/*.pas` and `lib/rtl/platform/esp/*.pas`.
Every name below is declared in exactly one of those files, and the
unattributed remainder is 0.6% / 0.8%.

| unit | riscv32 `--dce` | share | xtensa `--dce` | share |
| --- | --- | --- | --- | --- |
| pylib.pas | 1,112,916 | 53.6% | 825,056 | 47.5% |
| **pyeval.pas** | **624,684** | **30.1%** | **681,868** | **39.3%** |
| promocore.pas | 157,152 | 7.6% | 97,044 | 5.6% |
| builtinheap.pas | 84,300 | 4.1% | 58,868 | 3.4% |
| softfloat.pas | 39,048 | 1.9% | 29,268 | 1.7% |
| builtin.pas | 32,644 | 1.6% | 23,104 | 1.3% |
| everything else | ~24,000 | 1.2% | ~21,000 | 1.2% |

Do NOT compare the two ISAs' BYTES against each other: xtensa has 2- and 3-byte
instructions, so the same routine is smaller there, and the shares move for
that reason alone. Compare within a column.

The ten largest live bodies, riscv32, after DCE -- five of the top six are
pyeval's:

```
109396  PyHostCall              (pyeval)
 65284  PyBoundFnCallvnMaskBody (pylib)
 37056  CallBuiltin             (pyeval)
 35044  ParseMethodCall         (pyeval)
 33992  PyBoundPairCallKwBody   (pylib)
 30692  PyDynMethL              (pylib)
 29832  pyiter_has              (pylib)
 20920  pypercent_format        (pylib)
 20856  ParsePrimary            (pyeval)
 16900  PyClosureInvoke         (pylib)
```

## Why it is a bug and not merely large

`pyeval.pas`'s own header:

> *pyeval — a real exec()/eval() for the Python subset uforth's PYTHON-bodied
> words are written in … **NOT auto-used by NilPy yet**: build + test
> standalone first so a parse error here cannot break every NilPy compile.*

A program that never evaluates source at runtime is paying for a tokenizer, an
expression parser, a statement walker and a host-call trampoline. `Tokenize`
(38,024 B) IS dropped by DCE, which is the tell: the tokenizer had no live
edge, while `ParsePrimary`, `ParseMethodCall` and `DoAssignment` -- the layer
that would CALL the tokenizer -- are all live. A parser that survives while its
lexer dies is not being reached through a call; it is being held by a root.

## What to establish first, and it is an instrument

`--dce-report` answers "which bodies died". Nothing answers **"why is this body
live"**, and without that answer any attempt to shrink this is guesswork. The
root kinds DceRun installs are enumerable -- MethodFixups (a VMT/RTTI slot),
ProcAddrFix (`@proc`), InitProcs, FiniProcs, EntryRoot, the exported-symbol
loop, a stub-holding body, and a call from code no body owns. A per-body
"first root that reached it, and the edge chain from it" would name the
mechanism for all 624 KB at once.

**Do not start by deleting or guarding the unit.** The hook variables pylib
declares for pyeval to install into (`PyIterCallHook` and the rawKind=2 closure
registry, pylib.pas:164-174) mean some of this may be genuinely reachable from
NilPy code that uses closures or iterators -- which is most NilPy code. The
measurement says 30-39% is LIVE; it does not yet say how much is REACHABLE.
That distinction is the whole ticket.
