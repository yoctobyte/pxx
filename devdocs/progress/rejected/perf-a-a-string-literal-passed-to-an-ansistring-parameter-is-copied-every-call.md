---
slug: perf-a-a-string-literal-passed-to-an-ansistring-parameter-is-copied-every-call
track: A
prio: 70
type: perf
blocked-by: []
status: rejected
created: 2026-08-30
owner: frankB
summary: "REJECTED 2026-08-30 as SUPERSEDED -- do not re-land. The optimisation was real (849ms -> 84ms, measured correctly at the time) and is now worth NOTHING at the default level, because 440c822e6 promoted EmitStaticLitHandle from -O3 to -O2 THIRTY-SIX MINUTES after this landed and does the same job at codegen. Interleaved min-of-9 at HEAD: -O2 with=48ms without=41ms (no gain, marginally worse); -O1 with=50ms without=517ms (the 10x is real but only at -O1, which the owner has ruled in limbo). It also broke ~28 NilPy jobs and was reverted (72b4c47a7). The 2-line arg-tag change that fixes the NilPy break is NOT a standalone fix -- landed alone it is a FRESH regression (measured: 14 correct rows become one wrong line), because ASTTk[argVal] correctly describes what IRLowerCallArg produces on the unoptimised path. Net: land nothing."
---

# A string literal passed to an `AnsiString` parameter is copied on every call

- **Type:** perf (codegen / parameter marshalling) — **Track A** (shared core).
- **Found:** 2026-08-30 by frankB, diagnosing
  [[perf-p-parsefactorcore-walks-a-92-arm-name-chain-per-factor]] [P p60].
  That ticket attributes `ParseFactorCore`'s 9.4% to walking a 92-arm
  `CaseEqual` chain. It is not the walk — it is that **each arm allocates and
  copies a string**.

## Measured

Binary: HEAD, self-host fixedpoint `faf762981c3c` (= pin **v397**). `perf` is
unavailable here (`perf_event_paranoid=4`), so this is direct A/B timing.
5,000,000 iterations per row, same binary, same run:

| form | ms |
| --- | --- |
| `if n = 'await'` — inline compare against a literal | **19** |
| `if n = lit` — inline compare against a variable | 22 |
| `ByConst('await')` — literal into a `const AnsiString` param | **543** |
| `ByVal('await')` — literal into a by-value `AnsiString` param | 576 |
| `ByConst(S_AWAIT)` — typed `const S_AWAIT: AnsiString = 'await'` | **30** |

**It is a copy, not call overhead** — the cost scales with the literal's length.
Over 5M calls into a minimal `Length(s1)=Length(s2)` body:

| literal | ms |
| --- | --- |
| `'await'` (5 chars) | 791 |
| 40 chars | 2151 |
| pre-made variable | 51 |

## What the numbers separate

- **Inline comparison against a literal is already free** (19ms vs 22ms for a
  variable). So the literal itself is represented efficiently; nothing is wrong
  with string constants as such.
- **Parameter passing is where it goes wrong**, and `const` does not help. A
  `const` parameter cannot be mutated by the callee, so there is no semantic
  reason to copy at all — this is the arm that should be a pointer pass.
- **A typed constant costs 30ms where the identical literal costs 543ms.** The
  machinery to pass a string without copying already exists and is reached by
  one spelling and not the other. That is the shape
  `devdocs/dev/normalise-dont-special-case.md` is about: one concept, two
  paths, and only one of them is good.

## Why it is worth more than one function's profile

Every `CaseEqual(x, 'literal')` in the compiler pays it — `ParseFactorCore`
alone issues ~1.58M such calls, and the compiler is dense with the idiom
everywhere else. **And every pxx user program pays it**, at every call passing a
string literal to a string parameter, which is one of the most ordinary things
Pascal code does. It is invisible for the usual reason: the throughput curve
stays perfectly linear, so nothing looks pathological.

## Suggested direction (a hypothesis, not an instruction)

FPC gives a string constant a static representation with refcount `-1`, so
passing it is a pointer pass and the callee's release is a no-op. Whatever pxx
does at a literal-argument site, the typed-constant path already does something
equivalent — so the cheapest correct fix is likely to route literal arguments
through the same lowering the typed constant uses, rather than to invent one.
**Start by diffing the two paths' emitted code**, since one of them is already
right.

## Gate

Track A's: `make compiler/pascal26` byte-identical fixedpoint. The sharp oracle
for this specific change is `compiler.pas` in, `cmp` the two emitted binaries —
a marshalling change must not alter a single emitted byte, only the code that
does the marshalling. Then re-time the table above; the `const` row should
approach the typed-constant row.

## 2026-08-30 (frankB) — the arm is isolated: frozen literal -> MANAGED param, and only that

A third measurement narrows it from "string arguments" to one conversion.
5M calls per row, same binary, same run:

| form | ms |
| --- | --- |
| literal -> `const AnsiString` (managed param) | **561** |
| literal -> `const ShortString` (frozen param) | **32** |
| `AnsiString` variable -> `const AnsiString` | **31** |

So it is **not** that string parameters are slow, and **not** that literals are
slow. A literal into a *frozen* parameter is free, and a managed variable into a
managed parameter is free. **Only frozen-literal -> managed-`AnsiString`
allocates**, and that is the whole 18x.

That fits what the lowering already says about itself: `AN_STR_LIT` lowers to
`IR_CONST_STR`, whose value is a **frozen** static handle (`ir.inc:6006`, "the
frozen string's HANDLE — an 8-byte length prefix then the data"). Handing that
to a managed `AnsiString` parameter requires materialising a managed string,
and today that is a fresh heap allocation and copy on every call.

The **mirror** conversion is already written and is worth reading first: the
managed -> frozen arm at `ir.inc:3134` materialises a hidden temp and passes its
slot address, with a comment explaining that a managed handle "is never the
right layout" for a frozen slot. The defect is that the opposite direction
does the analogous thing *per call* for a value that is a compile-time constant.

### Where the fix is, and why I stopped

`IRLowerCallArg`, in **`compiler/ir.inc`** — contended Track A ground (frankA is
mid-ABI commit in that file; the coordinator refused a slot on it earlier today
for that reason). **Diagnosis only; the file is not edited.**

Direction, grounded in the table rather than invented: a string literal is a
compile-time constant, so its managed representation can be built **once, as
static data with an immortal refcount**, and the call can pass that handle
instead of allocating. FPC uses refcount `-1` for exactly this, which makes the
callee's release a no-op. The typed-constant row (30ms) shows a managed string
that is *already* static being passed with no allocation — so the target
representation exists in the compiler today and the literal arm simply does not
reach it. **Diff those two lowerings; do not design a third.**

### Gate note

`compiler.pas` in, `cmp` the two emitted binaries is the sharp oracle, but note
what it does and does not prove here: a marshalling change must leave the
emitted *program* byte-identical while changing the code that marshals. If the
`cmp` differs, the change altered semantics, not just cost.

## Gate — CORRECTED 2026-08-30 (frankB). My first version was inverted.

> **I wrote the gate below as "`cmp` identical = pass, `cmp` differs = the change
> altered semantics, a failure", and the coordinator endorsed it. It is WRONG
> for this ticket, and I caught it while taking the baseline rather than after.**
>
> That oracle was inherited from the *ParseFactorCore dispatch* ticket, where it
> is exactly right: a dispatch change resolves the same arm and must emit the
> same bytes. **This change is the opposite kind.** It is a marshalling change —
> it replaces an allocate-and-copy sequence with a pointer pass at every
> literal-argument call site. **Altering emitted bytes IS the change.** So:
>
> - `cmp` **differs** — expected, and says nothing about correctness on its own.
> - `cmp` **identical** — the change did **not take effect**. That is the
>   failure this gate should be watching for, and my version called it the pass.
>
> Two oracles of one name, one per ticket, and I carried the wrong one across.
> Naming the failing direction in advance is still right; I named the wrong one.

### What actually gates this change

1. **Self-host fixedpoint** (`make compiler/pascal26`). The strongest available
   behavioural oracle: the modified compiler must still compile itself to a
   fixedpoint. A marshalling bug that corrupts a string argument cannot survive
   a compiler compiling itself.
2. **Behavioural equality on emitted PROGRAMS, not bytes.** Compile the same
   sources with the pre- and post-change compilers and diff the **programs'
   output**. Bytes are expected to differ; behaviour must not.
3. **`test/test_widestring_lowering`** — `argLW = TakesWide('abcdef')` must stay
   **6**. This is the canary frankwasm pinned for exactly this interaction: their
   element-width conversion sits at the single tail of `IRLowerCallArg` on the
   assumption that every managed-string argument reaches `Result := value`. **If
   the literal arm is routed through an early `Exit`, that conversion silently
   stops firing and a literal into a wide parameter returns the wrong number of
   code units — no error, no crash.** Both hunks merge clean; this test is the
   only thing that says so. `test_widestring_element_positions` covers the same
   boundary from the element side.
4. **The harness ratio** (below): row 1 approaches row 3, rows 2 and 3 unchanged.

### The original wording, kept because the reasoning transfers to its own ticket



`make compiler/pascal26` byte-identical fixedpoint, then `compiler.pas` in and
`cmp` the two emitted binaries.

**State this before running it, not after:** the oracle proves the *emitted
program* is unchanged while the code that does the marshalling changes. So

- `cmp` **identical** = the change altered cost only. This is the pass.
- `cmp` **differs** = the change altered SEMANTICS, not just cost. **That is a
  failure, not an interesting result to investigate.** A marshalling fix that
  moves an emitted byte has changed what the compiler compiles.

Naming the failing direction up front is deliberate: a differing `cmp` on a
nice-looking diff is exactly the result that gets rationalised after the fact.

Then re-time the three tables above. The `literal -> const AnsiString` row
should approach the typed-constant row (~30ms); if it improves but stays well
above, the literal arm is reaching a *different* cheap path rather than the
constant arm's, and the diff is not finished.

### The harness, inlined so it outlives the session that wrote it

It was in a scratch dir, which dies with the session — the exact way a
"just ask me" offer turns into "rebuild it yourself". Save as `harness.pas`,
build with the compiler under test:

```pascal
program harness;
uses sysutils;
const S_AW: AnsiString = 'await';
function PAnsi (const s: AnsiString ): Integer; begin PAnsi  := Length(s); end;
function PShort(const s: ShortString): Integer; begin PShort := Length(s); end;
var i, h: Integer; t: array[0..3] of TDateTime;
begin
  h := 0;
  t[0] := Now; for i := 1 to 5000000 do h := h + PAnsi ('await');
  t[1] := Now; for i := 1 to 5000000 do h := h + PShort('await');
  t[2] := Now; for i := 1 to 5000000 do h := h + PAnsi (S_AW);
  t[3] := Now;
  WriteLn('literal  -> const AnsiString  ms: ', Round((t[1]-t[0])*86400000));
  WriteLn('literal  -> const ShortString ms: ', Round((t[2]-t[1])*86400000));
  WriteLn('variable -> const AnsiString  ms: ', Round((t[3]-t[2])*86400000));
end.
```

**Report the compiler's sha256 beside the numbers, every time**
(`sha256sum compiler/pascal26`). Two independent staleness routes make a number
meaningless without it, and both produce a confident wrong answer with no error:
`pinned` is a symlink so `git log` on that path reads the wrong history, and
**a `sync.sh` that pulled `compiler/**` leaves your binary a valid fixedpoint of
the PREVIOUS sources** — `make` still reports success, because it is not wrong,
just answering about a tree that has moved. **Rebuild after every sync before
re-timing**, especially when re-timing someone else's candidate fix, where a
stale binary produces a confident wrong verdict about THEIR work.

Read the RATIO, not the absolute times: this box runs several compiling sessions
at once, and a load average of 8 moves every row together. Two readings on the
same defect, different loads:

| binary | literal | ShortString | variable |
| --- | --- | --- | --- |
| `faf762981c3c` (pin v397) | 561 | 32 | 31 |
| `8adece5977d4` (HEAD `e04d9ae45`) | 849 | 42 | 44 |

Different absolutes, same ~19x. A candidate fix has worked when row 1 approaches
row 3 **and rows 2 and 3 are unchanged**.

## Log
- 2026-08-30 — resolved, commit 9588c8535.


---

## REOPENED 2026-08-30 (frankB) — landed, broke NilPy, reverted

`9588c8535` landed the win (849 ms -> 84 ms, unchanged ShortString/variable arms)
and `72b4c47a7` reverted its `ir.inc` hunk. **The optimisation is sound in
principle and the measurement stands; the guard was too wide.**

### The defect

```python
x = "a" * 3 ;  len(x)      ->  285      CPython and pinned: 3
a = "a" ;      len(a * 3)  ->  3        correct
               len(a+a+a)  ->  3        correct
```

**A string literal as the LEFT operand of repeat, and nothing else.** The same
value in a variable is correct. `print("a" * 3)` emits the RTTI type-name table
instead of `aaa` — it reads from a wrong base and runs until it hits something.
285 / 288 / 49982 are what a length field reads as when it is *not* the length
field.

### Attribution — measured, not inferred

frankwasm supplied `pinned` green / HEAD red plus the literal-vs-variable
boundary, and explicitly called it **a strong lead, not a verdict** (correlation
plus mechanism, with 55 commits in the window). Confirmed by **reverse-applying
this commit's `ir.inc` hunk alone and rebuilding**: 285 -> 3, binaries
`d0ff891ec0f2` (with) vs `9cc036445ccf` (without). The change was removed and the
symptom went with it.

### Why it was reverted rather than fixed

The failing population is **~24 `test-nilpy` jobs + 4 in `test-core`**, and
`test-nilpy` is **full-tier only** — the per-fix hook denies it. A fix I cannot
run against the red tests is a guess, and the pin was blocked behind this with
frank-optimize's `-O2` promotion waiting. Unblocking beat being clever.

### What the re-land needs

The suspected mechanism, **unverified and to be measured before acting on it**:
the NilPy repeat helper's path already resolves its source to the managed handle,
so my unconditional `+8` at the call boundary double-adds and the length is read
8 bytes off. If so the guard must exclude callees that do their own resolution
rather than assuming the parameter's `TypeKind` settles it.

**The condition frankwasm identified and I left implicit — write it down this
time.** I justified leaving `ParamWantsManagedStrTemp` alone with "managed ->
managed on a saturated refcount is a no-op", and *saturated is a property of the
OBJECT, not of the path*. The safety argument was contingent on a fact never
stated as a condition, which is how it read as unconditional.

### The gate lesson, which is the durable part

Eight string-heavy tests, both widestring canaries, `argLW=6` and `gate.sh quick`
were green at push time **and are still green now** — they were never wrong. The
affected population was invisible to every gate available: `gate.sh quick`
deliberately drops `test-nilpy` because it was 625 of the gate's 649 seconds.
**This is coverage geometry, not diligence** — the change landed exactly inside
the hole the quick tier is defined by.

The operational consequence is narrow and worth keeping: **a change to a
cross-frontend marshalling path has its affected population in a tier the author
cannot run.** The answer is not to widen the gate (that spends the machine that
produces Track T's median-8 sampling); it is to carry **one NilPy canary in the
evidence** for any change to argument marshalling. `x = "a" * 3` would have
caught this in under a second.


---

## REJECTED 2026-08-30 (frankB) — superseded in flight; land nothing

Re-opened to build the proper guard, and the measurement said not to. Recording
it in full because the *reasoning* is reusable and the conclusion is
counter-intuitive.

### The optimisation is worth nothing at the default level

Original harness (inlined above), HEAD, **interleaved A/B, min of 9, never
means**, load 8.4. A = my hunk re-applied, B = without it, nothing else differing:

| level | A (with opt) | B (without) | verdict |
| --- | --- | --- | --- |
| **-O2** (default) | 48 ms | **41 ms** | **no gain — marginally worse** |
| **-O1** | 50 ms | **517 ms** | 10x — real, but only here |

**My original 849 -> 84 ms was correct when it was taken.** What changed is
`440c822e6`, *"promote the static string-literal pass from -O3 to -O2, both
backends"* — `EmitStaticLitHandle` now does the same job one layer down, at the
default level. Timestamps:

```
9588c8535  20:07:45   my optimisation
440c822e6  20:43:52   the -O2 promotion   <- 36 minutes later
```

So this was **superseded in flight**, while it sat in the tree causing the NilPy
regression. Re-landing would restore a 60-line special case in `ir.inc` for zero
gain at the level everything is built at, and its only remaining benefit is at
**-O1, which the owner has ruled "in limbo"**.

This is `ir-as-substrate` working as designed: the general fix belongs at
codegen, where it applies to every literal, not at the call boundary behind a
guard listing the shapes I could think of.

### The arg-tag "fix" is NOT a standalone fix — it is a fresh regression

The NilPy break was `ir.inc:8848` tagging the `IR_ARG` with `ASTTk[argVal]` (the
argument's source type) rather than the parameter's. Re-tagging it to
`Ord(Procs[cpi].Params[0].TypeKind)` **does** fix `len("a" * 3)` — *with the
optimisation applied*: 14 probe rows byte-identical to CPython, `print("a" * 3)`
back to `aaa`.

**Landed WITHOUT the optimisation it BREAKS the same 14 rows** — measured, one
wrong line where fourteen correct ones belong.

So the conclusion I reached first was wrong and is worth stating so nobody
re-derives it: **`ASTTk[argVal]` was never the bug.** It correctly describes what
`IRLowerCallArg` hands back on the unoptimised path — a freshly copied managed
temp. The optimisation changed *what that call produces* without changing the
tag, and the two only ever agreed by accident. Neither half is independently
correct; they are one change or nothing.

I nearly landed the tag change on its own as a "latent correctness fix". The only
thing that stopped it was running the repro against a build that had **just** the
tag change — a control that felt redundant, because the fix was "obviously" a
strict improvement.

### What to do if -O1 is ever revived

Both halves together, as one commit, gated with `x = "a" * 3` in the evidence.
Not before — and check first whether `EmitStaticLitHandle` has been extended to
-O1 by then, which would supersede it again.

### The reusable half

1. **A perf win has a shelf life.** Between measuring and landing, someone can
   make it redundant one layer down. Re-time against HEAD before re-landing
   anything perf, especially after a revert — the tree you are returning to is
   not the tree you left.
2. **"My change measures as no difference" is data about the model, not a null.**
   The playbook says so; here it was the whole finding.
3. **Test the halves separately even when one is obviously subordinate.** The
   half I was sure was a strict improvement is a regression alone.
4. Measured `-O1` = 517 ms vs `-O2` = 41 ms on this row: **-O1 is 12x slower
   than -O2 on literal-heavy code.** Not this ticket's business, but relevant to
   whoever settles -O1's limbo.

---

## 2026-08-30 (frankS) — REJECTION CONFIRMED independently, and the recorded CAUSE above is wrong

I re-landed this before seeing the rejection, measured it properly afterwards,
and **discarded it**. Two things below are worth keeping; the verdict is not in
dispute.

### The rejection is right, and the -O sweep is worse for the change than recorded

The reopen note's "849ms -> 84ms" and my own "681 -> 76" were both measured
against a **pinned** compiler that predates `440c822e6`. That is not a control
for this change; it is a control for every improvement since the pin. Rebuilt
both arms on the SAME base (`649ec017c459` without, `756476085eb5` with) and
interleaved, min of 5-9:

| -O | without | with | |
| --- | --- | --- | --- |
| -O0 | 871 | 57 | 15.3x faster |
| -O1 | 540 | 51 | 10.6x faster |
| **-O2 (default)** | **46** | **48** | **no gain** |
| -O3 | 44 | 56 | **27% SLOWER** |

The -O2 row reproduces the rejection exactly. **The -O3 row is new and argues
against the change on its own**: `EmitStaticLitHandle` already produces the
static handle at codegen, so the IR-level rewrite is redundant work the later
pass then has to see through. This is not merely "worth nothing at the default"
— above the default it costs.

### The recorded CAUSE of the NilPy break is wrong, and a re-lander would inherit it

The reopen note says the repeat helper "already resolves its source to the
managed handle, so the +8 double-adds", flagged unverified. **It does not.** The
value was always right; the **`IR_ARG`'s TYPE TAG** was wrong. `IRLowerCallArg`
rewrites the literal into a managed handle, and the **caller** builds the
`IR_ARG` from the **source AST**, which still says `tyString` — so the backend
reads a frozen length prefix off a managed handle. 285/288/99964 are what a
length field reads as when it is not the length field.

The general argument loop was safe **by accident of an unrelated decision**: for
a non-lvalue into a `tyAnsiString` parameter it takes the
`ParamWantsManagedStrTemp` branch and hard-codes `Ord(tyAnsiString)`, so its tag
was never read off the AST at all. That is why `PAnsi('await')` worked and 8
string-heavy tests were byte-identical. A path that is correct for a reason
unrelated to the bug agrees with the broken version and the fixed one alike.

### The latent landmine, which outlives this ticket

**`IRLowerCallArg` decides an argument's representation; 36 callers
independently decide its type tag.** They agree only for as long as the
representation never changes. Anyone who later changes an argument's
representation — for this optimisation at -O0/-O1, or for anything else — walks
into it, and the search for affected sites is booby-trapped, because **the same
fact has two spellings**:

- `IRAppend(IR_ARG, v, -1, -1, 0, ASTTk[...])` — 17 sites
- `IRAppend(IR_ARG, v, -1, -1, 0, Ord(argTk))` where `argTk := IntToTypeKind(ASTTk[argVal])` — 3 sites

A grep for either returns something that reads like a complete population. Both
false completions were measured, in this order:

1. Fixing the one site the NilPy repro named made **every NilPy string test
   green** and still **segfaulted** `'abc' + f` — a Pascal operator overload with
   a literal operand (`ir.inc:9218`), which no NilPy test can reach.
2. Fixing all 17 `ASTTk[...]` sites then still failed `int("42")` with
   `ValueError: invalid literal for int() with base 10: '   @  x  ...'`.

The working shape, if anyone needs it, is on branch **`frankS-strlit-reland`**
(`6a58396b2`, not on master and not to be merged as-is): a marker recording the
node the rewrite produced, plus `IRCallArgTk(value, fallbackTk)` returning the
caller's original expression for every node but that one — **scoped by
construction rather than by enumeration**, so it does not depend on having found
every site. It also corrects one claim in the rejection summary: routed that
way, the tag change landed WITHOUT the optimisation is a no-op, not a fresh
regression, because the fallback *is* the old expression. Moot, since we land
nothing.

### The coverage lesson, corrected

The reopen note concluded the hole was `test-nilpy` being full-tier. It was not:
the affected jobs can be named individually and run in seconds, which is how the
"carry one NilPy canary" requirement was actually met here. **The hole is that
the entire failing population lived in ONE frontend, and the second defect was
in the other one.** A NilPy canary alone would have shipped the operator-overload
segfault.
