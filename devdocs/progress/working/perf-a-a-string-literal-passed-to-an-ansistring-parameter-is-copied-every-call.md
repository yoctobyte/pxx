---
slug: perf-a-a-string-literal-passed-to-an-ansistring-parameter-is-copied-every-call
track: A
prio: 70
type: perf
blocked-by: []
status: working
created: 2026-08-30
owner: frankB
summary: "Passing a string LITERAL to an AnsiString parameter allocates and copies it on every call — 28x slower than passing a typed constant, and the cost scales with the literal's length. `const` does not help, though by definition it needs no copy. Comparing against a literal INLINE is free, so this is parameter marshalling specifically. Compiler-wide: every CaseEqual(x,'lit') pays it, and so does every pxx program. Found while diagnosing perf-p-parsefactorcore, whose 9.4% is this defect rather than the 92-arm walk the ticket describes."
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
