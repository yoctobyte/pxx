# Project TODO

Single consolidated list of remaining work. Detailed plans live in their own
docs; this page links to them rather than duplicating. Ordering is rough
priority, not a contract — source and regression tests are authoritative.

Status legend: 🔴 bug · 🟡 partial · ⬜ not started · ✅ done (kept briefly to
correct stale notes elsewhere).

---

## 1. Standing bugs (fix first)

- ✅ **IR operator-overload segfault** — resolved. `test/test_op_overload.pas`
  now produces the correct `1 0 1 0 1 0 10 6` under the IR backend and `make
  test` runs the full suite to the fixedpoint check (exit 0). (Was: miscompiled
  at output line 5 then segfaulted; cleared by the 2026-05-30 IR index/stride
  fixes.)
- ✅ **String `+` concatenation** — works on the IR backend (the default) and
  legacy: `string+string`, `string+char`, `char+string`, and `char+char` all
  concatenate. (The old note described a pre-IR state.) Test:
  `test/test_char_to_string.pas`.
- ✅ **char → string coercion** (2026-05-30). `s := 'x'` (single-char literal),
  `s := someChar`, `s := Chr(n)`, and char-class-field stores now materialise a
  1-char string instead of segfaulting. Fix: IR_STORE_SYM/IR_STORE_MEM write
  `[len=1][char]` straight into the destination when the value is `tyChar`
  (`ir_codegen.inc` `IREmitStoreCharAsString`); parser types `char+char` as
  `tyString` so the concat path fires (`parser.inc` ~2338). No allocation, no
  stack leak. Test: `test/test_char_to_string.pas`.

---

## 2. Active arc — Lazarus/LCL enablement

**RTTI → published → streaming → resources → LFM.** Full phased, agent-
executable plan: **[`plan-rtti-streaming-lfm.md`](plan-rtti-streaming-lfm.md)**.

- Phase 0 ✅ class visibility parsing (`private/protected/public/published`;
  not enforced). Per-member published flag recorded for RTTI; see
  `test/test_visibility.pas`.
- Phase 1 ✅ RTTI emission (published-only, custom-minimal layout). Blobs +
  registry + `--dump-rtti` for **all** prop kinds — integer/ordinal, string,
  class, enum, set, method-pointer — plus published methods (`rtti_emit.inc`,
  `test/test_rtti_emit.pas`). Enum identity infra (`EnumType*`/`EnumVal*`,
  `LastTypeEnumId`, `UPropEnumId`) and named set types (alias table,
  `AliasTk=tySet`) both landed.
- Phase 2 ✅ reflection API (TypInfo-named), `compiler/typinfo.pas`. The whole
  path round-trips on the IR backend via `test/test_rtti.pas`: `GetClass` →
  `GetPropList` → `Get|SetOrdProp` → `Get|SetStrProp` → `GetMethodAddr` /
  `SetMethodProp` → set properties, matching the direct backend. Delivered by
  fixing general typed pointers (C1–C4 — see §4), the `__rttireg` registry
  intrinsic, and indirect call for method-backed props. Rationale archived in
  [`historic/phase2-handoff.md`](historic/phase2-handoff.md).
- Phase 3 ✅ streaming runtime (TReader-lite). `compiler/streams.pas`
  (TByteStream), `compiler/classes_lite.pas` (TComponent-lite + TReader),
  `typinfo.CreateInstance`. Walks our minimal TPF0 subset and instantiates +
  configures a component tree (int/string/bool/event props, nested children by
  class name). Tests: `test/test_streaming.pas`, `test/test_streaming_enumset.pas`.
  Enum (`vaIdent`→ordinal via enum RTTI), set (`vaSet` member-name list→bitset),
  and `vaLString` (4-byte length prefix) value-types now handled — props carry a
  typeRef to the element enum RTTI for both enum and set kinds.
- Phase 4 ✅ resource embedding. `{$R name file}` reads the file at compile
  time into Data and builds a table; runtime `resources.FindResource(name,
  data, len)` walks it via the `__resources` intrinsic (mirrors the RTTI
  registry / `__rttireg`). Test: `test/test_resource.pas` + `test/greeting.dat`.
  (Format is our own `{$R name file}`, not FPC's single-arg `{$R file.res}`.)
- Phase 5 ✅ LFM library. In-memory path (no file I/O yet): `.lfm` text embedded
  via `{$R}`, converted to TPF0 at runtime by `compiler/lfm.pas` (`TLfmReader` +
  `InitInheritedComponent`), streamed by Phase 3 `TReader`. `test/test_lfm.pas`
  + `test/test_lfm_form.lfm` run end-to-end in `make test` (string/int/enum/set
  props + child component; `Anchors=[akLeft,akBottom]` → 10 exercises set
  streaming). Two pre-existing showstoppers fixed to unblock it (2026-05-30):
  1. RTTI prop array was non-contiguous — `EmitPropInfo` interned prop-name
     strings *between* the per-prop record reservations, so `props[i]` (fixed
     64-byte stride) landed on string data → wild `NamePtr` → segfault. Fix
     (`rtti_emit.inc`): reserve the whole prop/meth array first, then fill.
  2. `uses typinfo` with no published class emitted NULL string literals:
     the `__rttireg` sentinel-drop in `compiler.pas` shifted `Fixups[]` with a
     whole-record array-element copy that the IR backend miscompiles in the
     main-program body (store no-ops). Fix: copy the record fields one at a
     time. Underlying codegen bug still latent — see memory note.
  Regression repro: `test/gui/repro_multiunit_rtti_segfault.pas`.

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

- 🟡 **General pointer syntax.** Typed-pointer path (Phase 2 unblock) done:
  - ✅ C1 named pointer aliases `PFoo = ^TFoo` (carry element type).
  - ✅ C2 pointer indexing `p[i]` read+write, stride = element size.
  - ✅ C3 record-pointer field access `p^.field` (deref a `^TRec` then field).
    Test: `test/test_ptr_deref_field.pas`.
  - ✅ C4 pointer casts `PType(expr)` preserving element type. `AN_PTR_CAST`;
    indexing a cast strides by the cast's pointed-at element size
    (`test/test_ptr_cast.pas`).
  - ⬜ pointer arithmetic `p + n` (currently unscaled/garbage; indexing is the
    working substitute). `@var` address-of works for `@arr[i]`/`@x`.
  See [`pascal-gap-analysis.md`](pascal-gap-analysis.md) §1.3.
- ⬜ **Float intrinsics.** `Trunc`, `Round`, `Int`, `Float` not implemented
  (float arithmetic/compare/write itself is done).
- 🟡 **Dynamic arrays.** Work for scalar elements. Missing: reference counting
  / copy-on-grow (content preserved), reclaim of freed blocks, `array of
  record` / `array of string`, and dynamic arrays as params / results.
- ✅ **Enums.** Type identity + ordinal↔name infra in place and used by RTTI
  (enum prop kind, EnumRTTI). Named set types (`set of TEnum`) also recognized.
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
- ✅ **Class string fields** — work with real strings (the earlier "garbage"
  was a misdiagnosis). Two distinct bugs were behind it, both now understood:
  - The `writeln(c.AnyField)`-as-sole-arg compile error was an IRVerify false
    positive (validated IR_CALL's `IRC`=classIdx as a node); fixed in `ir.inc`.
  - `s := 'x'` (single-char literal → tyString) segfaults — but that is the
    char-literal quirk below, **not** class-specific (it hits plain string vars
    and record fields identically). See "single-char string literal" in §4.

### Self-host papered-over gaps (real features the compiler dodges on itself)

These are masked by the bootstrap because the compiler never uses them on its
own source — exactly the class of bug that hid the op-overload segfault and the
string-`+` break. Not needed yet, but they are genuine missing/half features,
not eternal "constraints". Promote to fixes when convenient:

- ⬜ **`shl` operator.** Not tokenised at all (no `tkShl`); only `shr` exists.
  Compiler-side code uses `* 2^n` as the workaround. Add the operator + IR
  lowering so user code can shift left. (`lexer.inc` ~348/417/443 show the
  `*2`-instead-of-`shl` self-host dance.)
- ⬜ **`readln` / `read` statements.** *(user-requested, 2026-05-30 — wanted for
  library/interactive work.)* `tkReadln`/`tkRead` are lexed but never parsed as
  I/O statements (`tkRead` is only consumed as the property `read` keyword,
  `parser.inc:3505`). `write`/`writeln` are handled (`parser.inc:2666`); `read*`
  is the missing half. Needs runtime input plumbing too (SYS_READ from stdin,
  line buffer, parse into Integer/string/Char targets).
- 🔴 **Named result in a class method miscompiles.** In `function TFoo.Bar`,
  assigning `Bar := v` (function-name-as-result) segfaults — the name resolves
  toward a self method-call instead of the result slot. Plain (non-method)
  functions are fine (the compiler uses named results throughout). Workaround:
  use `Result :=` in all methods. Surfaced building `streams.pas`.
- 🔴 **Indexing a pointer-typed class field miscompiles.** `FField[i]` where
  `FField` is a `^T`/alias field returns garbage — the pointer-index fast path
  in `IRLowerAddress` only fires for an `AN_IDENT` base, not `AN_FIELD`. Same
  family as the ptr-cast stride fix (`d03fe17`), but the field path doesn't
  carry the pointed-at element type. Workaround: copy the field to a local
  pointer var, then index. Surfaced building `streams.pas`.
- ✅ **Single-char string literal / char → string** — fixed 2026-05-30. See the
  "char → string coercion" entry in §1.2 above. `s := 'x'`, `s := someChar`,
  `s := Chr(n)`, and char→string class/record fields all work now.
- 🔴 **Whole-record array-element copy miscompiles in main-program body.**
  `arr[j] := arr[j+1]` for an 8-byte record silently no-ops the store under
  some conditions inside the program's main body (IR backend). Surfaced in the
  `__rttireg` sentinel-drop loop (`compiler.pas`): dropped every Fixup, NULLing
  string literals. Does NOT reproduce standalone; fpc-built compiler is fine, so
  it is self-hosted codegen of `IR_STORE_MEM` for a record lvalue. Worked around
  field-wise (`Fixups[j].CodePos/.DataOff := ...`). Real fix pending — disasm the
  main-body record store. (2026-05-30)
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
