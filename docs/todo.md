# Project TODO

Single consolidated list of remaining work. Detailed plans live in their own
docs; this page links to them rather than duplicating. Ordering is rough
priority, not a contract — source and regression tests are authoritative.

Status legend: 🔴 bug · 🟡 partial · ⬜ not started · ✅ done (kept briefly to
correct stale notes elsewhere).

---

## 1. Standing bugs (fix first)

- 🔴 **IR operator-overload segfault.** `test/test_op_overload.pas`
  miscompiles under the IR backend (diverges at output line 5, then
  segfaults). Pre-existing on clean HEAD; makes the full `make test` die mid-
  suite. Use targeted tests until fixed. Fix lives in `ir.inc` lowering +
  `ir_codegen.inc` emit for the `__op__NN` overload procs.
- 🔴 **String `+` concatenation broken.** `tkPlus` on strings only emits
  `ADD RAX,RCX`; it never concatenates. Invisible to bootstrap (the compiler
  never concatenates strings via `+` on itself — it uses `AppendChar`). Real
  user code needs this. Until fixed, all string building must use `AppendChar`.

---

## 2. Active arc — Lazarus/LCL enablement

**RTTI → published → streaming → resources → LFM.** Full phased, agent-
executable plan: **[`plan-rtti-streaming-lfm.md`](plan-rtti-streaming-lfm.md)**.

- Phase 0 ✅ class visibility parsing (`private/protected/public/published`;
  not enforced). Per-member published flag recorded for RTTI; see
  `test/test_visibility.pas`.
- Phase 1 🟡 RTTI emission (published-only, custom-minimal layout). Blobs +
  registry + `--dump-rtti` done for integer/string/class prop kinds and
  published methods (`rtti_emit.inc`, `test/test_rtti_emit.pas`). Remaining:
  enum/set/method-pointer kinds (need enum name-table infra — enums are thin).
- Phase 2 🟡 reflection API (TypInfo-named). **Resume checklist + rationale:
  [`phase2-handoff.md`](phase2-handoff.md).** **Chosen unblock: fix general
  typed pointers** (architect decision) so blobs are walked in pure Pascal,
  rather than asm helpers/intrinsics. Done so far: typed-pointer C1+C2 (aliases,
  indexing — see §4). **Still needed before the RTL:**
  - C3 ✅ `p^.field` (record-pointer fields) — already wired via `AN_DEREF`
    branch in `IRLowerAddress` + `ResolveNodeRec`; no compiler change needed.
    Test: `test/test_ptr_deref_field.pas`.
  - C4 pointer casts `PType(addr)` — to turn an Int64/Pointer address into a
    typed pointer.
  - **Registry access**: a way for runtime Pascal to obtain the address of the
    RTTI registry blob (`RTTIRegistryOff`). Needs a finalize-time fixup (like
    `EmitDataRef`) since `RTTIRegistryOff` is only known after parse. A small
    codegen intrinsic (e.g. `__rttireg`) or a fixed head symbol is the likely
    path — asm can't (no relocation in the parse-time asm buffer).
  - **Indirect call** for method-backed props + events (`GetMethodAddr`/
    `SetMethodProp`): still unsolved by the pointer work — needs procedural-
    variable call or an IR `call_indirect`. Field-backed props (the common
    streaming case) do NOT need it; deliver those first.
  - Then `typinfo.pas`: `GetClass`/`GetPropInfo`/`GetPropList`/`Get|SetOrdProp`/
    `Get|SetStrProp` over the emitted blobs; `test/test_rtti.pas` round-trip.
- Phase 3 ⬜ streaming runtime (own TReader/TWriter-lite).
- Phase 4 ⬜ resource embedding primitive (`{$R}` / `FindResource`;
  independent — good parallel warm-up).
- Phase 5 ⬜ LFM library (text→binary tool + runtime glue).

GUI / LCL widget sets are pure library work **after** this arc — no further
compiler ask.

---

## 3. Interfaces  ⬜  (next big language feature, after the LFM arc)

The headline remaining language feature. The old gap analysis parked
interfaces "indefinitely" over COM/Windows baggage — **that rationale is
retired.** We do not need COM. Implement a lightweight, Linux-native model.
Detailed planning is a separate session; this is the scoping outline.

### Decisions to lock (in that session)

- **Reference-counting model.** Start **CORBA-style / no-refcount** (FPC's
  `{$interfaces corba}`): an interface is pure method dispatch — no
  `_AddRef`/`_Release`, no compiler-injected lifetime management. Add COM-style
  ARC (`TInterfacedObject` + auto `_AddRef`/`_Release` + exception-safe
  `try/finally` release injection on interface-typed locals) **later**. The
  refcount injection is the genuinely hard, error-prone part — defer it.
- **Root type.** Whether to require an `IInterface`/`IUnknown` base with
  `QueryInterface`/`_AddRef`/`_Release` slots. For the corba model these can be
  omitted; method slots only.
- **GUIDs.** Parse `['{...}']` and ignore initially. Only needed for
  `Supports`/`QueryInterface`-by-GUID. Optional.

### Mechanism (the real work)

1. **Parse** `type IFoo = interface [guid] <method signatures> end;` —
   signatures only, no bodies.
2. **Class implements**: `TBar = class(TParent, IFoo, IBaz)`. Bind each
   interface method to a class method by name + signature; error on unmet.
3. **Interface Method Table (IMT)** per (class, interface) pair, distinct from
   the class VMT. Pick the reference representation:
   - *Delphi-style*: object holds a hidden interface field pointing at the IMT;
     an interface ref points at that field; IMT slots are `Self`-adjusting
     thunks that fix the object pointer then jump to the class method; **or**
   - *fat pointer*: interface ref = `{IMT ptr, instance ptr}`; simpler `Self`
     handling, wider variable. Choose one and document it.
4. **Interface-typed variables**: storage per the chosen representation;
   class→interface assignment locates the class's IMT for that interface;
   method call loads the IMT and calls slot[k] with the carried instance.
5. **`is` / `as` / `Supports`**: type queries. Lean on the **class registry /
   RTTI from the LFM arc** for runtime class identity. Static cases can be
   compile-time-resolved first; `Supports(obj, IFoo, out ref)` checks whether
   the class implements `IFoo`.
6. **Operators**: assignment, identity `=`/`<>`, param passing, function
   results.

### Prerequisites & ordering

Needs solid class/VMT (have) and runtime class identity (the LFM arc delivers a
class registry — reuse it). Hence ordered **after** the LFM arc. Interfaces are
**not** a streaming prerequisite.

**Synergy:** the `Self`-adjusting IMT thunks are a clean use of the new inline
asm, or a small dedicated IR op.

**Out of scope / decide later:** `implements` delegation, interface
inheritance depth, method-resolution clauses, COM ARC.

---

## 4. Language gaps (smaller, opportunistic)

- 🟡 **General pointer syntax.** Progress (Phase 2 unblock — typed-pointer path):
  - ✅ C1 named pointer aliases `PFoo = ^TFoo` (carry element type).
  - ✅ C2 pointer indexing `p[i]` read+write, stride = element size.
  - ✅ C3 record-pointer field access `p^.field` (deref a `^TRec` then field).
    Already wired; test: `test/test_ptr_deref_field.pas`.
  - ⬜ C4 pointer casts `PType(expr)` preserving element type (currently
    `PType(x)` errors "undefined variable" — casts parse as function calls).
  - ⬜ pointer arithmetic `p + n` (currently unscaled/garbage; indexing is the
    working substitute). `@var` address-of works for `@arr[i]`/`@x`.
  See [`pascal-gap-analysis.md`](pascal-gap-analysis.md) §1.3.
- ⬜ **Float intrinsics.** `Trunc`, `Round`, `Int`, `Float` not implemented
  (float arithmetic/compare/write itself is done).
- 🟡 **Dynamic arrays.** Work for scalar elements. Missing: reference counting
  / copy-on-grow (content preserved), reclaim of freed blocks, `array of
  record` / `array of string`, and dynamic arrays as params / results.
- 🟡 **Enums.** Type handling exists; **verify completeness for RTTI** —
  streaming needs ordinal↔name (Phase 1 dependency).
- 🟡 **Generics.** Template mechanism exists; breadth vs FPC unverified.
- ✅ **Class visibility.** Phase 0 of the LFM arc done (see §2).
- ⬜ **Method-call-with-args as a statement.** `obj.Method(arg)` on its own
  line fails parse (`Expected: :=` — the statement parser treats `obj.Method`
  as an lvalue). No-arg method statements (`obj.Reset`) work, and arg'd calls
  work in expression context. Statement-position arg'd method calls are the
  gap. Surfaced writing `test/test_visibility.pas`.
- ⬜ **Nested `{ }` comments.** The self-hosted lexer ends a `{` comment at the
  first `}`, so a `{` inside a comment breaks self-compile (`unexpected
  character`). FPC accepts nested comments (warns "comment level 2"). Avoid
  inner braces in compiler-side comments until fixed. Surfaced in Phase 1.
- 🔴 **String field on a class reads/writes as garbage.** `obj.FStr := 'x';
  writeln(obj.FStr)` on a class string field printed an address, not the
  string (record string fields work — see `record_string_field.pas`). Class
  layout/codegen for string fields differs. Surfaced writing
  `test/test_rtti_emit.pas`; blocks streaming string props until fixed.

### Self-host papered-over gaps (real features the compiler dodges on itself)

These are masked by the bootstrap because the compiler never uses them on its
own source — exactly the class of bug that hid the op-overload segfault and the
string-`+` break. Not needed yet, but they are genuine missing/half features,
not eternal "constraints". Promote to fixes when convenient:

- ⬜ **`shl` operator.** Not tokenised at all (no `tkShl`); only `shr` exists.
  Compiler-side code uses `* 2^n` as the workaround. Add the operator + IR
  lowering so user code can shift left. (`lexer.inc` ~348/417/443 show the
  `*2`-instead-of-`shl` self-host dance.)
- ⬜ **`readln` / `read` statements.** `tkReadln`/`tkRead` are lexed but never
  parsed as I/O statements (`tkRead` is only consumed as the property `read`
  keyword, `parser.inc:3505`). `write`/`writeln` are handled (`parser.inc:2666`);
  `read*` is the missing half. Needs runtime input plumbing too.
- ⬜ **Single-char string literal typed as `tyChar`.** `'x'` is `tyChar`, not a
  1-char string, so string vars must init as `s := ''` then `AppendChar`.
  Decide: context-coerce char→string on assign/concat, or leave as documented
  dialect quirk. (String `+` itself = standing bug §1.2.)
- Note: "integer-only compiler tables" stays a deliberate **constraint**, not a
  bug — it is the fixedpoint-safety convention, nothing to fix.

### Recently resolved (corrects stale notes in gap-analysis / older memory)

- ✅ `break` / `continue` — implemented (`parser.inc` ~2687/2693).
- ✅ Sets (`set of T`, literals, `in`, algebra) — implemented.
- ✅ `with` statement — implemented.
- ✅ Floating point (Single/Double/Extended, arithmetic, compare, Write) —
  implemented, IR parity done.
- ✅ Inline assembler (rudimentary) — see [`inline-asm.md`](inline-asm.md).

---

## 5. Backend & targets

- ⬜ **Delete the frozen direct backend** (`codegen.inc` / `GenAST`) once fully
  confident in IR. Until then keep it compiling but add **no** features to it.
- ⬜ **Additional CPU targets**, per [`roadmap.md`](roadmap.md): i386 →
  aarch64 → arm32 → RISC-V bare metal. Each must pass the fixedpoint gate.
- 🟡 **Inline asm depth** — see [`inline-asm.md`](inline-asm.md) TODO:
  labels/branches (highest value), global-var operands, explicit `[reg]`
  memory + SIB, operand-size keywords, AT&T syntax.

---

## 6. Compiler-internal refactor (last / cosmetic)

- ⬜ **`.inc` → real `.pas` units.** The include soup is an accepted single-
  translation-unit hack, not the target architecture. The inline-unit model
  (`unit/interface/implementation`, `uses`) already supports the move — no
  separate-compilation feature needed. **RTL/library units move early**
  (low risk, real payoff); the **compiler self-split is last** (stress-tests
  unit support against the compiler itself, must hold self-host fixedpoint,
  human-readability payoff only). Write new code as proto-units meanwhile.
  Seam principle: algorithm/table → library; token-stream + symtab plumbing →
  core (`asmenc.inc` is the live example to split).

---

## Cross-cutting rules (apply to all work)

- IR backend only; `codegen.inc` frozen.
- Self-host constraints: no `shl` (use `*2^n`); no string `+` on hot paths
  (use `AppendChar`); init strings via `''` + `AppendChar`; keep compiler-side
  tables integer-only for fixedpoint safety.
- Validate with `make bootstrap` (fixedpoint) **and** by running each feature's
  regression test under the self-built compiler — fixedpoint alone is not
  correctness.
- Commit per logical unit; never push without explicit confirmation.

---

## Note on `pascal-gap-analysis.md`

That document is **partially superseded**: it lists sets/floats as gaps (now
done) and parks interfaces "indefinitely" (now planned — see §3). Treat this
TODO and the linked plans as current; refresh the gap analysis when convenient.
