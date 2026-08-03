# Type identity as substrate

Companion to `ir-as-substrate.md`. That note says: push generality DOWN into the
core, keep frontends thin. This one says where we failed to do that — in the
type system specifically — and what the general case actually is.

## The invariant we do not currently hold

> A value's type is decided ONCE, where the value is introduced, and is CARRIED.
> No later stage re-derives it from node shape, token text, or position.

Every bug in the table below is a violation of exactly that sentence.

## Evidence (measured 2026-07-19, not estimated)

One session of Track N work produced these, all silent, no diagnostics:

| symptom | what was dropped |
| --- | --- |
| by-value `Variant` param read garbage | "slot holds a pointer" re-decided per backend; `tyVariant` missing from all 6 |
| `o.inner.name` printed a raw pointer | `AddUField(..., REC_NONE)` — field lost its class |
| `x = o.inner` printed a raw pointer | `Syms[].RecName` not set from a field RHS |
| `len(s.split(","))` segfaulted | `PyInferLastCi` not set for a class-returning method |
| `-> bool` printed `1`, `-> float` returned `0` | methods registered with a hardcoded `tyInteger` |
| `s[0].upper()` produced a NUL | char->string conversion keyed on node SHAPE, not type |
| `"a" + "b".upper()` gave `AB` not `aB` | postfix binding re-decided per parse route |

Three surveys of the tree:

1. **~90+ distinct sites store "which type is this."** Not 90 concepts — the
   SAME ~8-field tuple redeclared per entity kind:
   ```
   SymPtrBaseTk/Rec  AliasPtrBaseTk/Rec  UFldPtrElemTk/Rec
   ProcRetPtrElemTk/Rec  CTypeFnRetPBaseTk/Rec  LiftCapPtrTk/Rec
   ```
   and the same again for `*Tk`, `*Rec`, `*ElemTk`, `*ElemRec`, `*ProcSig`,
   `*DynDepth`, `*ArrLen`. Symbols alone carry ~26 such locations.

2. **The "param slot holds a pointer" rule is written 8 times and 3 copies
   disagree.** x86-64 / aarch64 / arm32 test `IsRef, IsArray, frozen-string,
   tySet, tyVariant`; i386 and riscv32 omit `tySet`; `ParamSize` omits both
   `tySet` and `tyVariant`; `AllocParam` omits `tySet`. `ParamSize` and
   `AllocParam` are meant to encode ONE rule and already contradict each other.

3. **10 separate expression-type inferences exist**, but only NilPy is an
   outlier: `pyparser.inc` has EIGHT token-scanning functions
   (`PyInferExprType` et al) that work on TOKENS, never the AST. Rust
   (`rparser.inc:1036`) and Zig (`zparser.inc:942`) already do the right thing —
   parse the initialiser, read `ASTTk[node]`. C needs none.

## What the two layers actually get wrong

- **AST under-carries.** `ASTTk` is a bare kind; identity is RECOMPUTED on
  demand by `ResolveNodeRec` walking node shapes, and record ids are smuggled
  through `ASTIVal`. Recomputing-from-shape is the documented
  `project_string_conversion_shape_blindspot_pattern`.
- **IR under-carries worse, and the backends compensate by bypassing it.**
  `IRTk` is a bare kind; identity rides `IRA`/`IRB`/`IRC` positionally per
  opcode, with `IRSetLenBaseRec` as a dedicated side-channel. Because that is
  not enough, backends read `Syms[]` directly:
  ```pascal
  (Syms[symIdx].Kind = skParam) and (Syms[symIdx].IsRef or ... )
  ```
  **That is the architectural break.** The IR claims to be the substrate, but a
  backend cannot be written against the IR alone.

## The design

### 1. `TypeRef` — name the tuple that already exists ten times
One value `(kind, recId, elemTk, elemRec, ptrBase, procSig, dynDepth, arrLen)`
carried declaration -> expression -> IR -> ABI. This is a COLLAPSE, not an
invention, which is what makes it viable under a byte-identical gate.
Kills the "one of six side arrays not written" bug class, and turns
`project_symtab_alloc_parallel_array_landmine` ("Alloc* must reset ALL fields")
from a rotting checklist into one assignment.

### 2. Frontend typing: make NilPy do what Rust and Zig already do
NOT a new engine — the correct pattern is already in-repo and proven. NilPy
diverged for a real reason (Python declares locals implicitly by assignment, and
a type can WIDEN across branches, so all assignments must be seen before the
frame is laid out). The fix is therefore a pre-pass over the **AST**, not over
tokens: parse the body, walk it to collect and widen local types, then emit.
Note `PatchProcPrologue` already patches frame size after the body, so
allocate-as-you-go is structurally possible.

### 3. A real declaration phase
Today `PyRegisterClassShells` registers NAMES, bodies are typed, MEMBERS are
registered last. That ordering is why a field pre-pass had to be bolted on.
Collect all declarations — shells, members, signatures — before typing any body.

### 4. ABI oracle; backends barred from `Syms[]`
Split what is portable from what is per-target:
- **portable, in the IR:** this is a 16-byte managed variant; this is class #7.
- **per-target, NOT in the IR:** register or memory, 4 or 8 bytes, hidden-dest
  or `rax`. Freezing these into the IR breaks cross-compilation.

So: the IR carries portable identity; a per-target oracle answers
`PassBy(t)` / `ReturnVia(t)` / `SlotHoldsPointer(t)`; backends consult the
oracle and **never touch `Syms[]`**. That last clause is the enforceable
invariant. Under it the `Variant` bug is one oracle line instead of six backend
edits, and the `-> str` method crash cannot happen, because `AN_CALL` and
`AN_VIRTUAL_CALL` stop deciding independently.

## Honest caveats

- **A falsifiable prediction FAILED.** From divergence (2) I predicted a `set`
  param would misbehave on i386/riscv32 and work on x86-64. Tested on five
  targets: all agree (`has a` / `no z`). Sets reach params via `IR_LEA` on a
  materialised temp (`ir.inc:3563`), not the param-slot path, so the
  disagreement never fires for that shape. **The divergence is LATENT, not
  active.** Do not sell this work as "fixing live bugs" — sell it as removing a
  class of future ones. Nobody can currently say which of the 8 copies is
  authoritative, and no test would catch a fourth drifting.
- `RetViaHiddenDest` does NOT cover `tyAnsiString` (managed strings return a
  heap handle in a register). Any oracle must not assume "aggregate" == "hidden
  dest".
- Items 1 and 4 are Track A ground under the self-host byte-identical gate;
  2 and 3 are frontend-local under `test-nilpy`. They cannot land as one change.
  Land `TypeRef` ADDITIVELY (nothing reads it), migrate consumers per lane.

## How we know it worked

Metric, not vibes: **adding one new type kind that is passed by pointer and
returned via hidden dest currently requires edits at 9 independent sites**
(2 param-sizing + 1 return + 6 backend param-detection). After the work it must
require ONE. If it still takes six backend edits, the abstraction failed however
clean it looks.

## The compiler's OWN structs are a second identity space (2026-08-03)

A late-found instance of the same invariant break, worth its own section because
it is the one place where getting it wrong corrupts the compiler building
itself.

`TSymbol`, `TParam` and `TProc` exist **twice**: once as ordinary Pascal record
declarations in `defs.inc`, and once as hand-written *builtin-mirrored* layouts
so the compiler can self-host (`symtab.inc:1114`):

```pascal
REC_TSYMBOL = 6;   REC_TPARAM = 7;   REC_TPROC = 8;   { all < REC_UCLASS_BASE = 16 }
```

Member resolution then splits on that id, and the builtin half was deliberately
lax — `RequireRecMember`'s own comment: *"Builtin records keep the lax path —
their field names are compiler-authored."* Which is true, and is exactly why the
lax path was wrong: a name that is compiler-authored and does not match is
always a **typo**, never a probe.

What it cost, measured: `Procs[i].Params[j].ProcSig := -1` — `TParam` has no
`ProcSig` — compiled with no diagnostic, took `RecFieldType`'s not-found default
(`tyInteger`, **offset 0**), clobbered a neighbouring field, and segfaulted an
unrelated NilPy test in the `quick` tier. FPC rejected the same source outright.
Fixed by rejecting in `RecFieldType`'s builtin branch
(`bug-pascal-unknown-record-field-accepted-in-compiler-source`).

Three things to carry forward:

1. **A duplicated type declaration is a duplicated identity, and the copies get
   different rules.** Same failure shape as the ~90 sites above, but between the
   *language's* view of a record and the *compiler's* view of the same record.
   `ValidateBuiltinRecordLayout` checks the two agree on LAYOUT; nothing checked
   they agree on which members exist.

2. **"Compiler-authored, therefore trusted" is backwards.** Hand-written and
   unvalidated is where a typo has no other net. Every user record was already
   checked; only the compiler's own structs were not.

3. **Minimal repros cannot find this class.** Four were tried, and every one is
   correctly rejected, because a user record gets `recId >= 16`. The bug is
   reachable ONLY when a record is builtin-mirrored — i.e. by the compiler
   compiling itself. When a minimal case refuses to reproduce something the real
   tree does, suspect a second identity space rather than a subtle shape.

The tooling lesson is in `debugging-playbook.md` terms: this was settled in one
step by building a `-g` compiler, breaking on the miss path and reading the
backtrace — after several minimal-repro guesses had settled nothing.
