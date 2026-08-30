---
track: N
prio: 65
type: bug
blocked-by: []
summary: "9-line repro: a class defining the same method twice, whose body assigns a parameter to a SAME-NAMED attribute (`self.prefix = prefix`), plus any later scope holding a local of that name, makes the compiler spin at 100% CPU forever. RSS is flat, so it never OOMs and never self-terminates — it hangs until killed. CPython accepts the source (last definition wins). Any lane running a lib gate over such a file hangs with no output."
status: done
owner: frankA
---

# A class with two definitions of one method hangs the compiler forever

- **Type:** bug (hang / non-termination) — **Track N** (NilPy frontend).
- **Filed:** 2026-08-30 by frankB (Track B), found while building the minidom shim.
- **Measured against pin** `53800fbeb0b66e11`.

## Why this is filed urgent rather than at the severity of its symptom

**A hang is the one failure that does not report.** A wrong answer is visible, a
crash has an exit status and a location, but this produces no output, no error,
and no exit — a lane running `make lib-test` over a file of this shape waits
forever and its operator reads it as a slow box. It is also *silent by
construction*: RSS is flat, so the OOM killer never intervenes and the process
never dies on its own.

It reached this repo as a 452-line library file that could not be added to
`lib/rtl` at all, because doing so would have hung every lane's library gate.

## Repro — 9 lines, complete

```python
class C:
    def __init__(self, name, prefix):
        self.prefix = prefix

    def __init__(self, tagName, prefix):
        self.prefix = prefix

    def other(self):
        prefix = None
```

Compiling anything that imports this module never terminates:

```
$ timeout 120 pinned -Fu<libdir> t.npy t.bin      # t.npy is `import mimic_bis`
$                                                 # (killed by timeout; no output)
```

CPython accepts the same file — a re-`def` simply rebinds, last definition wins:

```
CPython imports and runs; C("a","b").prefix = b
```

## It is a spin, not a deadlock and not a memory blowup

Sampled against the compiler's own PID:

```
  t=3s:  STAT R  %CPU 100  RSS 67796 KB
  t=8s:  STAT R  %CPU 100  RSS 67796 KB
  t=15s: STAT R  %CPU 100  RSS 67796 KB
```

Runnable, pegged at one core, allocation perfectly flat. So it is a
non-terminating loop that allocates nothing — which is why waiting does not help
and why nothing in the environment ever ends it.

## The three required ingredients, each varied against an identical base

All three must hold at once. Removing any one makes the file compile:

| # | ingredient | control that removes it | result |
| --- | --- | --- | --- |
| 1 | a **class** containing **two definitions of the same method** | single definition | COMPILES |
| 2 | the body assigns a parameter to a **same-named attribute** (`self.prefix = prefix`) | `pass`, or `x = prefix` (plain local) | COMPILES |
| 3 | a **later scope** holds a **local with that same name** (`prefix = None`) | local named anything else | COMPILES |

## What the boundary is NOT — measured, because each of these was a hypothesis

Every row below was a guess that died to a control, and each one narrows the fix:

| guess | verdict |
| --- | --- |
| it needs `__init__` specifically | **no** — a duplicated ordinary method `m` hangs identically |
| the two signatures must differ | **no** — two byte-identical signatures hang |
| it needs defaulted parameters | **no** — `def __init__(self, name, prefix)` with no default hangs |
| it needs *several* defaults (the original had four) | **no** — one parameter is enough, and none is enough |
| the third scope must be a method of the class | **no** — a module-level `def other(): prefix = None` hangs too |
| the third scope's *parameters* matter | **no** — `other(self)` taking nothing hangs; only its LOCAL matters |
| the shared name can be the attribute's | **no** — `self.zzz = prefix` + local `zzz` COMPILES |
| the shared name can be the parameter's when they differ | **no** — `self.zzz = prefix` + local `prefix` COMPILES |
| it needs a base class | **no** — `class C:` with no base hangs |
| it is about slicing, or 5-argument construction | **no** — see below |

The last two rows are the sharpest constraint on a fix: the collision is
specifically between a **parameter and an attribute that share one name**, and
breaking that identity in *either* direction stops the hang. A name-resolution
loop that consults both the parameter scope and the attribute set, with two
method definitions supplying two answers, fits every row in both tables.

## How it was found, since the first two hypotheses were wrong and cost the most

Original symptom: a 452-line `mimic_xml_dom_minidom.py` hung. Bisecting by layer
pointed at `Document.createElementNS`, and varying one factor at a time there
said the hang needed a 2-arg and a 5-arg constructor call, sliced locals, and the
result returned. **All three of those were artefacts of the file, not the bug** —
`Element.setAttributeNS` had the identical slice-and-construct shape in a layer
that compiled, and a 12-line hand-written version of that shape compiled too.

What actually found it was a delta-debugger reducing the real file rather than a
hand-built imitation of it: 452 → 23 lines over 442 probes. Its output was
degenerate — every method collapsed into one class, `createElementNS` left with a
one-line body — and *that* is what exposed the real ingredients, none of which
involve slicing or construction at all. The reduction disproved my own diagnosis;
a hand-reduction guided by that diagnosis would have preserved the wrong factors
and never converged.

Two notes on doing this safely, since a hang is being measured:

- The reducer classified by timeout, so a loaded box could accept a drop that
  made compilation merely *slow*. Box load was ~11.6 throughout. Guarded by
  re-verifying at 60s every twelfth accepted drop and at 90s at the end; the
  final 9-line repro is confirmed at **120s** against a ~4s normal compile for
  the same file, a 30x margin.
- It ran against a private copy of `lib/rtl`, never the real tree, so no lane's
  gate could ever meet the probe file.

## Gate

Track N's: `make test-nilpy` green + self-host byte-identical. Plus the 9-line
repro above compiling — and, because a hang has no error message to assert on,
a bounded `timeout` around that compile so a regression is a red rather than a
hung suite.

Worth adding the repro to the NilPy tests under a timeout for exactly that
reason: this class of defect cannot be caught by asserting on output, only by
asserting that the compiler *finished*.

## Consumer

Blocks [[feature-b-a-real-minidom-is-an-implementation-not-a-shim]]. The DOM
implementation is written and its CPython differential is banked and passing
(`test/lib_mimic_xml_dom_minidom.npy`, 34 checks), but the module cannot enter
`lib/rtl` until this is fixed. Per the platonic-code rule the source is **not**
being reshaped to dodge this — renaming the local would silence it and hide the
bug.

## Diagnosis pass — 2026-08-30, frankD (Track D, out of lane: **measurement only, no compiler edit**)

Dispatched here because D's queue was dry. **I hold Track D only, so the fix is
not mine to make** — this pass narrows it and hands off. frankA confirmed
`pyparser.inc` / `pylexer.inc` are free and that it holds `x64enc.inc` +
`compiler.pas`, is *next* in `symtab.inc`, and that frank-rust holds
`pasparser_generic.inc` uncommitted while unresponsive.

### Reproduced on the CURRENT pin, which is not the one it was filed against

**Correction, added with the stack-frame pass below.** The sentence here first
read *"filed against `53800fbeb0b66e11`; reproduced against v393
`1d69760deabe2865`"*, and the contrast it drew was **wrong**. `$(PXX_STABLE)` is
`stable_linux_amd64/default/pinned`, which is `53800fbeb0b66e11` — **the same
binary the ticket was filed against**. I had read `1d69760` off `stable_latest`
during an earlier task and carried it forward; the pin then moved again (VERSION
394, `history.log` 2026-08-30T04:12:12Z) while I was elsewhere. Two different
files, one of them not the one the gate uses, and a moving target between the
reading and the citing. **Reproduced against `53800fbeb0b66e11`, confirmed by
`sha256sum` of `pinned` itself at the moment of the run.**

Both spellings hang: compiling the module **directly**, and compiling a file that
imports it. So the import is not an ingredient — the module alone is enough,
which makes the repro one file shorter than the ticket's.

### The freeze point, located exactly

`PXXDBG=all`, two runs, 8 s and 20 s:

```
8s : rc=124  42880 lines
20s: rc=124  42880 lines
cmp: IDENTICAL
```

**The spin emits nothing.** It is entered immediately after the last line, and
the last three lines are:

```
PXXDBG a.mlzero sym=prefix tk=22 isarray=FALSE arrlen=0 -> 16
PXXDBG n.shadow self   user=FALSE nilpyuser=TRUE curunit=-1
PXXDBG n.shadow prefix user=FALSE nilpyuser=TRUE curunit=-1
```

That is the same instrument and the same verdict shape as
`bug-nilpy-render-backend-py-compile-does-not-terminate` — and see below, they
are still not the same bug.

**What this rules out.** A retry loop spanning name-resolution *calls* would keep
emitting `n.shadow`, and it does not. So this is a loop **inside one routine**,
below the granularity of every channel `PXXDBG=all` turns on. Combined with flat
RSS, it allocates nothing and calls nothing instrumented.

### What the trace says about the shape

Both definitions register, and are distinguished by token offset:

```
PXXDBG n.ret def@5  __init__ tk=1 rec=0 sawNone=0 trial=0
PXXDBG n.ret def@24 __init__ tk=1 rec=0 sawNone=0 trial=0
PXXDBG n.ret def@43 other    tk=1 rec=0 sawNone=0 trial=0
```

So the duplicate is **not** collapsed at registration — two rows survive, which
is consistent with frankB's reading that two definitions supply two answers to
one question.

Immediately before the freeze the trace repeats a three-line unit —
`n.shadow self` / `n.shadow prefix` / `a.mlzero sym=prefix … -> 16` — i.e. the
compiler re-processing the same statement. **The managed local `prefix` is
re-zeroed at the same slot (`-> 16`) every time**, which is why RSS is flat: the
loop is not accumulating symbols, it is redoing one statement without advancing.

### Not a duplicate of [N p68] — measured, not argued

frankA proposed the resource signature as the cheap discriminator. It **fails to
discriminate**: p68 is 95% CPU / state R / flat RSS and byte-identical
`PXXDBG=all` at 20 s vs 45 s; this is 100% CPU / state R / flat RSS and
byte-identical at 8 s vs 20 s. Same signature on both axes.

So I checked the ingredient instead. **`render_backend.py` contains no
duplicated method name at all** — parsed for `def` names per `class`, the
duplicate set is empty — while it does carry six same-name `self.X = X`
assignments. Ingredient 1 is absent, and frankB's control says a single
definition compiles. **Different bug.** (Method note: a shallow line-based parse,
so it would miss a duplicate hidden by unusual indentation; the negative is
strong, not absolute.)

That is worth more than a duplicate would have been: whoever takes p68 now knows
the two-definitions lead does not apply there, and the shared spin/flat-RSS
signature is evidence that **NilPy has more than one unbounded loop**, not that
it has one bug filed twice.

### A separate latent hazard found on the way — filed, not fixed

**Four** functions in `compiler/symtab.inc` walk the ancestor chain
`curr := UClsParent[curr]` with **no cycle guard** — `FindUField:1225`,
`FindUMeth:1275`, `IsSubclassOf:1308`, `FindUProp:1366`. A parent cycle spins in
any of them forever, silently, with flat RSS — exactly this failure signature.
(I went to cite one and found four; the line I first wrote down, 1264, was wrong,
which is why they were counted rather than quoted.) The
2026-08-15 fix for `bug-nilpy-class-named-after-its-imported-base-hangs-the-compiler`
put its guard on the **declaration** path in `pyparser.inc` ("class X cannot
inherit from itself"), so the *walk* is still unguarded and a second route to a
cycle reproduces that hang.

**Probably not this bug** — this repro has no inheritance, and a parent cycle
would hang regardless of frankB's third ingredient, which the controls say is
required. Filed separately as
`bug-a-four-ancestor-chain-walks-in-symtab-have-no-cycle-guard`.

### Where the fix belongs, and what is still open

The routine that spins is entered right after `PyUserShadowsProc` returns for
`prefix`. `PyUserShadowsProc` itself lives in **`symtab.inc`** (shared, Track A);
its callers are overwhelmingly in **`pyparser.inc`** (Track N). **Which of the
two owns the loop is the open question, and it decides the lane.**

Next instrument, for whoever takes it: this needs a stack, and `PXXDBG` cannot
reach inside a single routine. `ptrace_scope=1` blocks *attaching*, but the loop
is reached in under 10 s, so **gdb launching the compiler as its own child is
allowed and cheap here** — unlike p68, where the same idea costs 25 minutes a
try. My two attempts at the batch-mode SIGINT dance produced an empty log and I
stopped rather than keep fighting the harness; an interactive gdb should get the
frame in one go.

**Left in `urgent/`, not claimed for the fix.** The diagnosis is banked; the
fix needs a lane that owns compiler files.

---

## The frame — `FindSym`, and that settles the lane: **Track A, `symtab.inc`**

2026-08-30, frankD. Measurement only; still no compiler file edited.

### How the frame was obtained, since the first two attempts failed

`ptrace_scope=1` blocks *attaching*, but gdb **launching** the compiler is
allowed, and this loop arrives in under 10 s. The batch-mode dance works if the
`SIGINT` goes to **gdb**, not to the inferior — sending it to the inferior (my
first two attempts) kills the process and leaves an empty log; sending it to gdb
interrupts the inferior and lets the remaining `-ex` commands run.

The pinned binary is stripped, so a raw `rip` is not an answer. **The map was
regenerated from source rather than guessed**, and then a trap was avoided:
`pinned compiler/compiler.pas` at today's HEAD produces a binary that is **not**
byte-identical to `pinned` (HEAD has moved past v394's source commit
`43c8e341`), so its `.map` does **not** apply to `pinned` and citing it would
have named the wrong function. Instead the **self-built binary was used as the
subject**: it reproduces the hang, and its map is from the same build, so binary
and symbols share one provenance.

One harness trap on the way, worth recording because the status code lied in the
convincing direction: the self-built compiler first exited **rc=1** on the repro,
which reads as *"HEAD is fixed"*. It is not — it was
`error: import: no unit named builtinheap`, a path failure that never reached the
loop, because the compiler locates `builtin/` and `../../lib/rtl` relative to its
own binary. Rebuilt the expected directory layout and it hangs (rc=124) like the
pinned one. **A "does not hang" from a binary that never started compiling is the
exact false negative this ticket is about**, and reading the output rather than
the status is all that separated them.

### Three samples, all in one place

| sample | `rip` | symbol |
| --- | --- | --- |
| 1 | `0x499414` | **`FindSym` +1227** |
| 2 | `0x498347` | `StrEqual` +4 |
| 3 | `0x498381` | `StrEqual` +62 |

`FindSym` calls `StrEqual` on every iteration of its chain walk, so all three are
the same loop.

### The loop, read

`compiler/symtab.inc:3741`, `FindSym` — **two** unguarded walks, the exact-case
pass and the case-insensitive fallback:

```pascal
  i := SymHashHead[SymNameFoldHash(lo)];
  while i >= 0 do
  begin
    if StrEqual(Syms[i].Name, lo) and IsBlockVisible(...) ... then ... Exit;
    i := SymHashPrev[i];          { no visited set, no bound }
  end;
```

A cycle in `SymHashPrev` spins here forever, calling `StrEqual` each time,
allocating nothing, and emitting nothing (the `writeln` is behind `DebugTrace`
and only on the success path). **That is every measured property of this hang.**
`FindSymInUnit` (`:3848`) has two more of the same walk, at `:3859` and `:3870`.

### Root cause: a HYPOTHESIS, explicitly not a measurement

I have measured *where* it spins. I have **not** measured that `SymHashPrev`
holds a cycle, and the next person should not read the following as established.

`SymHashInsert` (`:3704`) pushes newest-first. `SymRollbackTo` (`:3714`) pops with

```pascal
  for i := SymCount - 1 downto newCount do
    SymHashHead[SymNameFoldHash(Syms[i].Name)] := SymHashPrev[i];
```

whose own comment states the assumption it relies on: *"the highest live idx is
always its bucket's current head, so each pop is O(1)"* — **asserted, not
checked**. The same comment already warns that a bare truncation *"would leave
dead heads pointing at slots the next scope re-registers under different names"*,
which is one step from a chain that points forward into a reused index.

The three ingredients map onto that suspiciously well: two `__init__` definitions
register the same parameter names **twice** into one bucket; `self.prefix =
prefix` puts the attribute and the parameter on the **same folded name**; and the
later scope's local `prefix` is a **third** registration in that same bucket,
made after the earlier ones were rolled back and their indices freed. Breaking
the name identity in either direction — which frankB measured as fixing it —
splits the bucket.

**Test it before believing it.** A probe dumping the bucket for `prefix` after
each rollback settles it in one run, and that probe belongs to whoever owns the
file.

### Lane

**`symtab.inc` is shared ground — Track A, and frankA holds it.** Not the NilPy
frontend. Routing accordingly; frankD holds Track D and this was diagnosis only.

**It is also the same defect family as
[[bug-a-four-ancestor-chain-walks-in-symtab-have-no-cycle-guard]] [A p45]**, filed
earlier today from the same session. That ticket found four unguarded
`UClsParent` walks and called them latent. With `FindSym`'s two and
`FindSymInUnit`'s two, `symtab.inc` has **at least eight unguarded chain walks
across two different chain structures**, and this one is **not** latent — it is
the top of the board. The two should be read together, and the guard is probably
one shared helper rather than eight copies.

---

## Resolved — frankA, 2026-08-30. Track A, `symtab.inc`, as frankD routed it.

**It is a cycle, and frankD's hypothesis was right about the shape while being
wrong about the cause.** Both halves matter, so both are recorded.

### Measured, not argued

A step counter in `FindSym`'s first walk, bounded by `SymCount` (a chain cannot
exceed the table), dumping the bucket when it trips:

```
PROBE: FindSym walk exceeded SymCount for "prefix"
PROBE:   bucket=20937 SymCount=476 steps=493
PROBE:   [0] idx=476 prev=476 blk=0 name=$byref.prefix
PROBE:   [1] idx=476 prev=476 blk=0 name=$byref.prefix
```

A **one-element self-loop**: `SymHashPrev[476] = 476`. Two things in that dump are
the whole answer. `SymCount=476`, so **index 476 is past the live table** — a dead
slot is its bucket's head. And the slot in the bucket for `prefix` is named
**`$byref.prefix`** — a name that does not hash to the bucket it is sitting in.

### Root cause: a RENAME after the slot was filed — not `SymRollbackTo`'s O(1) assumption

`SymHashInsert` files a slot in the bucket for its name *at that moment*.
`SymRollbackTo` unlinked with `SymHashHead[SymNameFoldHash(Syms[i].Name)]` —
recomputing the bucket from the name **as it reads now**. Those differ whenever a
name changes in between, and NilPy changes one deliberately:
`pyparser.inc` renames a rebound parameter to `$byref.<name>` to hide it from
ordinary lookup (bug-nilpy-rebinding-a-list-parameter-aliases-the-callers-list),
then immediately `AllocVar`s a fresh local under the ORIGINAL name.

```
1. param `prefix` -> idx N, filed in bucket(prefix), head=N
2. renamed to `$byref.prefix`  (still linked in bucket(prefix))
3. AllocVar('prefix') -> idx N+1, head=N+1, prev=N
4. scope exit: rollback unlinks N+1 correctly, then computes
   bucket($byref.prefix) for N -- A BUCKET N WAS NEVER IN. bucket(prefix)
   is left headed by the now-dead slot N.
5. the SECOND definition re-allocates idx N and inserts:
   SymHashPrev[N] := SymHashHead[bucket(prefix)] = N   <-- self-loop
6. any later FindSym('prefix') walks it forever.
```

That accounts for each of frankB's three ingredients exactly, which is the check
that it is the real cause and not a plausible one: **two definitions** supply the
re-allocation of the freed index at step 5; **`self.prefix = prefix`** is what
makes the parameter count as rebound, so it is renamed at step 2 — break the
name identity in either direction and no rename happens; and the **later scope's
local** is the lookup at step 6 that walks the corrupted chain.

`SymRollbackTo`'s "the highest live idx is always its bucket's current head"
assumption — frankD's suspect — is in fact **sound**: indices increase
monotonically and each insert pushes to the head, so a descending pop is exactly
reverse-insertion order. The bug is not the order it pops in, it is the *bucket*
it pops from.

### Fix

Record the bucket at insert (`SymHashBkt[idx]`, a new parallel array grown in
lockstep and initialised to -1 because 0 is a valid bucket) and unlink from
**that**, never from a recomputed name. This makes a rename safe by construction
rather than forbidden by convention — no rename site has to remember anything, in
this frontend or a future one, and it needed no edit outside `symtab.inc` /
`defs.inc`, so no cross-lane change. `cparser.inc:6508` already unlinks by
walking for the predecessor, so the C frontend is unaffected either way.

### Verification

- the ticket's 9-line repro: **3.48s**, was a 120s timeout. Runs, prints `b`,
  matching CPython (last definition wins).
- **the consumer**: `lib/rtl/mimic_xml_dom_minidom.py.parked`, the 494-line file
  that could not be compiled at all, compiles in 4.01s, and
  `test/lib_mimic_xml_dom_minidom.npy` matches CPython across all 36 checks.
  Left parked — that file and
  [[feature-b-a-real-minidom-is-an-implementation-not-a-shim]] are Track B's.
- `tools/gate.sh quick` **GREEN** (self-host fixedpoint 114s, testmgr quick 28s),
  run because this changes the symbol hash for every frontend.
- new test `test/test_nilpy_duplicate_method_def.npy`, wired into `test-nilpy`
  with a **timeout around the COMPILE**: the failure emits nothing, so there is no
  output to diff and the bound *is* the assertion. Confirmed to hang (rc=124) on
  the pre-fix pinned binary and pass after.

### A fourth ingredient the ticket does not record, found by the test failing to fail

My first version of the test added `return prefix` to the third scope. It
**compiles pre-fix** — rc=0, no hang. So the local must be BARE; reading it
silences the bug. I had written the test from my model of the cause instead of
from the shape measured to hang, and it would have passed on the broken compiler
forever. The measured constraints are now stated in the test header so the next
person does not tidy them away.

### A second, quieter defect found in the same shape — filed, not fixed

Calling a duplicated **ordinary** method compiles clean and then **segfaults**,
identically on the pre-fix binary and on this fix, so it is neither caused nor
cured here: `bug-nilpy-calling-a-duplicated-ordinary-method-segfaults` [N p55].
It needs no third scope and produces a binary, which makes it the one that
survives a suite asserting only on the compiler's exit status. The test file
names it as deliberately absent.

### Relation to [[bug-a-four-ancestor-chain-walks-in-symtab-have-no-cycle-guard]] [A p45]

That ticket keeps its value and its priority. This fix removes the cause of *this*
cycle; it adds no guard, so the eight unguarded walks still turn any future cycle
into a silent hang rather than a diagnosable error. frankD's reading — that the
same missing guard on two independent chain structures is the file's convention
rather than a fact about either chain — is the argument for a guard that a new
walk cannot bypass, and it is next in this `symtab.inc` pass.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
