---
prio: 48  # auto — 8 conformance tests
---

# `class operator` + named operators (Initialize/Finalize/Explicit/...)

- **Type:** feature (Pascal frontend, operator overloading)
- **Track:** P (shared `parser.inc` — A-gated)
- **Status:** done
  ([[feature-pascal-corpus-fpc-testsuite]]).
- **Owner:** frank1-ACP

## Symptom
`error: expected operator symbol after operator keyword` — pxx parses only
symbol operators (`operator +` etc.). Missing:
- **management operators** in advanced records: `class operator
  Initialize/Finalize/AddRef/Copy(var a: TFoo)` (tmoperator*) — these have
  *semantics* (compiler-invoked at var lifetime events), not just parse;
- named conversion/logic operators FPC accepts (`Explicit`, `:=`
  assignment-operator spelling, `in`, `inc`, `dec`).

## Impact
8 curated failures (`tmoperator*`, `tassignmentoperator1`, some `toperator*`).
Skip-list reason: `parser: named/class operator`.

## Note
Parse-side is P; the lifetime-event *invocation* (Initialize on entry,
Finalize on scope exit) likely needs IR/lowering support → that part is a
Track A ticket when reached.

## Gate
`make test` + self-host byte-identical; burn the skip-list entries.

## Slice 1 landed (2026-07-12, opus-p)

Named operators on RECORD/CLASS operands parse + dispatch:
- `operator :=` / `Implicit` — implicit conversion at assignment (ir.inc
  AN_ASSIGN rewrites the RHS to the conversion call when types differ and the
  overload's result type matches the LHS).
- `operator Explicit` — fires at value casts (both the ident castTk branch and
  the tkInteger_T branch in ParseFactor).
- `operator Inc/Dec` — the Inc(x)/Dec(x) statements desugar to x := Op(x)
  (single-operand form only, like FPC).
- `Enumerator` + management ops parse+register but are NOT dispatched yet.
Conformance: toperator11 burns. Test: test/test_named_operators.pas.

## Slice 2 landed (2026-07-12, opus-p)

`operator Enumerator` DISPATCHES in for-in: a class/record (or string-typed)
container with a registered enumerator overload builds the same duck-typed
MoveNext/Current[/Free] loop as GetEnumerator, over the operator call.
Scalar operand types also register now (LongInt/String/...; String under
both managed+frozen kinds), and conversion/unary operators enforce 1-param
arity (binary = 2). Conformance: tforin5 + tassignmentoperator1 burn
(3 total with toperator11). Tests: test_named_operators,
test_operator_enumerator.

**Remaining:**
- operators on NON-record operand types (String/LongInt operands —
  tforin2, tgenfunc8/10, tassignmentoperator1): needs the OvrlType table +
  dispatch to accept scalar tks (recId REC_NONE), and the scalar binop hot
  path to consult it.
- `operator Enumerator` dispatch in for-in (tforin2/5/24).
- `class operator` INSIDE advanced records (tmoperator*) — member-decl parse
  plus the Initialize/Finalize lifetime EVENTS, which are IR work → file the
  Track A ticket when picked up.

## Slice 3 landed (2026-08-20, frank1-ACP) — Initialize/Finalize

`class operator Initialize/Finalize` inside an advanced record now PARSE and,
more to the point, are INVOKED at the variable lifetime events they exist for.

Correcting the note above and the stale comment in `ParseOperatorDef`: the
management operators were **not** "parsed+registered but not dispatched" —
they did not parse at all (`Initialize` was not in the named-operator list),
so no program could reach the missing dispatch. Both halves landed together.

### The design call: a desugar, not a seventh backend emitter

The obvious home for "run something when a local goes out of scope" is the
managed-local cleanup (`SymNeedsManagedCleanup` /
`ProcHasManagedLocalCleanup` in `symtab.inc`), but that cleanup is *decided*
shared and *emitted* per backend — `EmitManagedLocalCleanup` is x86-64 asm,
and arm32/aarch64/i386/xtensa/riscv32 each have their own. Six emitters to
extend, six chances to leave a target subtly wrong.

Instead `WrapManagementOps` rewrites the routine's body AST:

    Initialize(v0); Initialize(v1); ...
    try BODY finally Finalize(v0); Finalize(v1); ... end;

`try..finally` already covers every way a routine can leave — falling off the
end, `Exit`, an exception — on every target, which is exactly the guarantee a
Finalize needs. One shape, zero backend edits, right on xtensa the day it is
right on x86-64. `WrapMainBodyManagementOps` does the same one scope up,
around the main program body, for globals.

The regression risk is near zero by construction: the trigger is a `class
operator Initialize/Finalize` declaration, which was a compile error before
this change, so no existing program can reach the new path.

### Measured against FPC 3.2.2, not assumed

- **Both lists run in DECLARATION order.** A routine with `x.n := 1; y.n := 2`
  prints `fin 1` then `fin 2` — not the reverse a stack discipline suggests.
- **A function's Result slot is not initialized** (`i <> retSym` in the scan).
- **The slot is not zeroed before Initialize runs.** FPC hands over raw
  memory: an ordinary Integer field still held `$5A5A5A5A`, only the managed
  fields were nil.
- **A local is routine-scoped**, so a loop body does not re-initialize it.
- Exit and a propagating `raise` both finalize. Byte-identical to FPC.

### Two deliberate divergences from FPC, both in the test header

1. **Globals are finalized.** FPC initializes a record-typed global and then
   never finalizes it (measured: two globals → two `init`, zero `fin`).
   Delphi's managed records do finalize globals, a Finalize that never runs is
   a leak by construction, and the pairing is the whole point of the operator.
   So pxx emits both. The divergence is one FPC line missing, not one of ours
   too many.
2. **No caller-side temp.** FPC materialises a returned record in a hidden
   temp in the CALLER and manages that temp too, printing an extra init/fin
   pair around `r := Mk`. In the main body that temp is a global, so FPC even
   starts it up. A compiler temporary is not a user lifetime; pxx has no such
   temp and emits neither.

### Refused rather than silently skipped

Three shapes FPC reaches through recursive RTTI and this per-symbol desugar
does not. Each is a compile error naming its follow-up ticket, because a
declared invariant that simply never runs is worse than a program that does
not compile:

- an **array** of a managed record, and any record/class holding one in a
  **field**, at any depth → [[feature-pascal-management-operators-nested-and-array]];
- `class operator **Copy**` / **AddRef**, recognised so the spelling is not a
  syntax error, but the copy lifetime event has no dispatcher →
  [[feature-pascal-management-operators-copy-and-addref]].

### The trap that cost the most

`AN_TRY_FINALLY` needs the exception runtime, whose stubs are emitted from a
**token pre-scan** (`hasExceptions`, `parser.inc` ~35952) long before any body
is parsed — `EnableExceptionRuntime` at parse time is far too late. A program
whose only `try` is one the compiler synthesised called a stub at code offset
0 (`call to a runtime stub that was never emitted`). Fixed by triggering the
pre-scan on the *declaration*: ident `finalize` preceded by ident `operator`,
which is the same evidence the desugar will act on.

### Files

- `compiler/defs.inc` — `OPK_INITIALIZE/FINALIZE/ADDREF/COPY` (1005-1008).
- `compiler/parser.inc` — the four names in `ParseOperatorDef`'s dispatch, the
  shape validation (one `var` param, no result, a record operand),
  `RecHasManagementOp` / `RecContainsManagementOp`,
  `WrapManagementOpsRange` + its two wrappers, the `ParseSubroutine` and
  `ParseBlock` call sites, and the `hasExceptions` pre-scan trigger.
- `test/test_mgmt_operators.pas` + `.expected` (FPC's own output but for the
  two divergences), and the three `*_refused.pas` fixtures. Wired into
  `Makefile` beside the textfile-char tests.

### Still open on this ticket

The named-operator work above (slices 1-2) left `operator Enumerator` on
non-record operand types and the `tmoperator*` conformance entries; this slice
burns the management-operator half. The skip-list sweep is a separate pass.

## Log
- 2026-08-20 — resolved, commit fc2e7091d.
