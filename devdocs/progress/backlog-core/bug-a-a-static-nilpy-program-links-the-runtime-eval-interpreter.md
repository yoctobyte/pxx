---
track: A+N
prio: 60
type: bug
status: open
found: 2026-09-20
found-by: frankS
blocked-by: []
summary: "MEASURED, not estimated: after `--dce`, compiler/builtin/pyeval.pas is 624,684 B of a riscv32 ESP image's 2,074,812 (30.1%) and 681,868 B of xtensa's 1,736,175 (39.3%), for a program that never calls eval() or exec(). pyeval is a runtime tree-walking interpreter written for uforth's PYTHON-bodied words, and its own header says `NOT auto-used by NilPy yet`. Its single largest routine, PyHostCall, is 109,396 B by itself -- 5.3% of the whole image in one body. DCE drops only 13.7% of the unit (723,548 -> 624,684) against 30.7% of the image overall, so something ROOTS most of it rather than calling it: the suspects are the @proc / VMT / RTTI root classes (an address in a table is reachable from anywhere by construction) and pylib's hook variables that pyeval installs into. ANSWERED 2026-09-20 by `--dce-why`, built for this ticket: on xtensa the ENTIRE eval tree hangs off ONE @proc-taken root -- `PyHostCall <- PyFieldGet <- DoAssignment <- ExecStatement <- ExecSuite <- CallUserFn <- PyBodyTramp <- [@proc taken]` -- so the mechanism is a trampoline whose ADDRESS is in a table, not a call from NilPy code; 4 @proc roots hold 17,420 B directly and drag the rest through ordinary call edges. On riscv32 the same tree is rooted EARLIER and more coarsely: 819,480 B across 128 bodies are held because a stub target lands INSIDE them (143 stub targets, 139 inside a body, against xtensa's 4 and none), so that ISA cannot even see the @proc chain. PRICED 2026-09-20 and the @proc was a DECOY: the real root is pyeval's `initialization` doing `PyIterCallHook := @PyCallKey1`, an address that IS written by code that always runs, and PyCallKey1 reaches the interpreter through ONE arm -- `pyclosure_call1`, whose PyClosureInvoke saves the interpreter's own state and runs a body through ExecStatement. Removing that single arm drops xtensa live code 1,721,914 -> 824,155 B (-52%); removing the whole initialization drops it to 712,617 (-59%). riscv32 shows ZERO for both, because its stub-target rule roots the same bodies independently. The design is to route that arm through a hook installed by exec()/eval() -- the only two entries that can mint a closure -- so the pass can SEE that a program with no eval cannot reach it. Rung of umbrella-an-esp32-image-is-as-small-as-it-can-be: it is the single largest identified component of an ESP NilPy image after DCE."
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

## The instrument now exists, and it answered this -- 2026-09-20

`--dce-why` (and `--dce-why=<substring>` for a named body) prints, per live
body, the FIRST root that reached it and the CHAIN of call edges from that
root. Built for this ticket; positive control in `test/test_dce_why_root_report.pas`,
asserted in `test-quick`.

**Live bytes by first reason, same program, same flags as the table above:**

| first reason | riscv32 | xtensa |
| --- | --- | --- |
| called by (an ordinary call edge) | 1,033,892 B / 589 | 1,531,910 B / 589 |
| holds a stub target | **819,480 B / 128** | **0** |
| vmt/rtti slot | 200,544 B / 149 | 172,637 B / 149 |
| @proc taken | 15,784 B / 4 | 17,420 B / 4 |
| called from unowned code | 1,712 B / 5 | 1,006 B / 5 |
| total live | 2,071,412 B | 1,722,973 B |

**The xtensa column is the one that names the mechanism**, because nothing
there is masked by the stub-target rule:

```
173755B  PyHostCall <- PyFieldGet <- DoAssignment <- ExecStatement
                    <- ExecSuite <- CallUserFn <- PyBodyTramp <- [@proc taken]
 51743B  PyBoundFnCallvnMaskBody <- pyboundfn_callvn_mask <- pyboundfn_callvn
                    <- pyboundfn_callv <- PyCallKey1 <- [@proc taken]
```

So pyeval is **not** kept by a call from the compiled Python program. It is kept
because `PyBodyTramp`'s ADDRESS is taken -- an entry in a table, which is
reachable from anywhere by construction -- and everything the trampoline can
reach follows by ordinary call edges. Four such roots account for the whole
tree. That is the thing to design against; `pyeval`'s size is the symptom.

**And it says why the riscv32 number was uninformative:** there, 143 stub
targets exist and 139 of them land INSIDE a body, so `DceRangeHoldsStub` roots
those 128 bodies before the reachability walk ever runs and the @proc chain is
never the FIRST reason for anything. See
[[bug-a-riscv32-dce-keeps-135-more-bodies-than-xtensa-on-one-program]].

**Keep LIVE and REACHABLE apart when quoting any of this.** Every row above is
a CONSERVATIVE claim by the pass -- "an address of it is in a table" is not "it
runs". The report's own header says so.

**Do not start by deleting or guarding the unit.** The hook variables pylib
declares for pyeval to install into (`PyIterCallHook` and the rawKind=2 closure
registry, pylib.pas:164-174) mean some of this may be genuinely reachable from
NilPy code that uses closures or iterators -- which is most NilPy code. The
measurement says 30-39% is LIVE; it does not yet say how much is REACHABLE.
That distinction is the whole ticket.

## 2026-09-20 (frankS) — PRICED TO ONE LINE, and it is not the @proc

The `--dce-why` chain named `PyBodyTramp <- [@proc taken]`, so the first move
was to ask whether that address needs taking. It does not — the one site is
inside `EvalPyStmts`, which DCE itself drops.

**That produced a real fix worth far less than it is worth knowing.** An
`@proc` inside a body the same pass deletes **writes nothing**, because the
code that would store the address never runs — so it is an **EDGE**
(owner → target), not a root, and only an `@proc` in code no body owns roots
anything. `"an address in a table can be called from anywhere"` is a claim
about the SOURCE; the pass has the answer about the IMAGE.
**The soundness argument rests on one thing, and it was already true:** a body
kept because something jumps INTO it is marked live, so its `@proc` sites still
root their targets. Without that, a retained body would hold the address of a
removed one.
The chain now spells `<- X` (X calls it) apart from `<- @X` (X takes its
address), so a later reader cannot quote the weaker claim as the stronger one.

**It bought 1,036 B.** That is the honest result of the lead: the `@proc` was a
decoy, and the same report then named the real root.

**The real root is `pyeval.pas`'s `initialization` section**, which runs in
every program that links the unit:

```pascal
initialization
  PyIterCallHook := @PyCallKey1;
```

That address IS written, by code that always runs, so the pass is right to root
it. `PyCallKey1` then reaches the whole interpreter through ONE arm:

```
PyHostCall <- PyFieldGet <- DoAssignment <- ExecStatement
           <- PyClosureInvoke <- pyclosure_call1 <- PyCallKey1
           <- [@proc taken in unowned code]
```

**Both halves PRICED BY REMOVAL — a measurement, not a proposal.** Each
removal breaks the program; they exist to price an edge. xtensa,
`examples/esp32/nilpy-c3`, `--dce`:

| tree | live code |
| --- | --- |
| HEAD | 1,721,914 B |
| with the whole `initialization` removed | 712,617 B (**−1,009,297, −59%**) |
| with ONLY `if pyclosure_is(key) then ... pyclosure_call1` removed | 824,155 B (**−897,759, −52%**) |

So **one line of one dispatcher is 52% of the image.** Neither removal is a
proposal — both break the program — they price the edge.

**Why riscv32 shows nothing for either: 2,070,376 B both times.** Its
stub-target rule roots 128 bodies independently, so the interpreter stays live
whatever happens to this edge. Fix that ISA's rung separately
([[bug-a-riscv32-dce-keeps-135-more-bodies-than-xtensa-on-one-program]]) or the
win here will not appear there.

### The design this points at, and the invariant it rests on

`PyClosureInvoke` saves and restores the INTERPRETER's own state (`TkKind`,
`TkText`, `Cur`, `LclN`, `FnN` ...) and runs a body through `ExecStatement`. A
closure of that kind can only EXIST if `exec()`/`eval()` created it. So in a
program that never calls either, `pyclosure_is(key)` is always False and the
arm is dead — but it is dead in a way **only the program's behaviour knows and
the pass cannot see**, which is precisely why it costs 897 KB.

Give the pass something it CAN see: route that arm through a second hook
(`PyClosureCallHook`, say) installed by `PyExecSrc`/`EvalPyStmts` — the only
two entries that can mint a closure — instead of calling `pyclosure_call1`
directly. `PyCallKey1` then references no interpreter, and the tree hangs off
`exec()` where it belongs. The unconditional install of `PyIterCallHook`
STAYS: it fixed a real bug
(`bug-nilpy-min-max-with-a-key-held-in-a-variable-picks-the-numeric-overload`)
and lazy installation is what caused it.

**LIVE, not REACHABLE, still.** Nothing above says the interpreter runs in this
demo; it says the pass cannot prove it does not. The proposal is a way to make
the proof structural rather than a claim.
