# Project TODO

Single consolidated list of remaining work. Detailed plans live in their own
docs; this page links to them rather than duplicating. Ordering is rough
priority, not a contract — source and regression tests are authoritative.

Status legend: 🔴 bug · 🟡 partial · ⬜ not started · ✅ done (kept briefly to
correct stale notes elsewhere).

---

## 1. Standing bugs (fix first)

Front-end syntax/typing issues (comments, `GetMem(p,size)`) investigated +
planned in **[`plan-pascal-syntax-issues.md`](plan-pascal-syntax-issues.md)**.


- ✅ **IR operator-overload segfault** — resolved. `test/test_op_overload.pas`
  now produces the correct `1 0 1 0 1 0 10 6` under the IR backend and `make
  test` runs the full suite to the fixedpoint check (exit 0). (Was: miscompiled
  at output line 5 then segfaulted; cleared by the 2026-05-30 IR index/stride
  fixes.)
- ✅ **String `+` concatenation** — works on the IR backend (the default) and
  handles `string+string`, `string+char`, `char+string`, and `char+char`
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
  `SetMethodProp` → set properties. Delivered by
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

---

## 2b. GUI arc — GTK3 widgetset + LFM-streamed UI  ✅ (vertical slice)

Full doc: **[`gui.md`](gui.md)**. An LCL-compatible GUI on GTK3 (Linux/X11)
where a form's structure and event wiring come from an `.lfm`. Demos in
`test/gui/` (`test_lcl_lfm.pas` is the end-to-end one). Contrary to the earlier
"pure library, no compiler ask" expectation, it needed several general
compiler features — all landed and in `make test`:

- Direct Pascal `external 'soname'` shared-library binding (FFI without a C
  header). `EmitExit` switched to `exit_group`, and the bump heap moved from
  `brk` to `mmap` so it never collides with libc/GTK `malloc`.
- 16-byte stack alignment at external SysV call sites (GTK uses aligned SSE).
- `@routine` → code pointer; `@obj.method` → `TMethod` (of-object events).
- `const` record params passed by reference (were truncated to 8 bytes).
- Virtual **procedure**-call statements are now emitted (only virtual functions,
  as expression operands, worked before).
- Each class's VMT is filled by inheritance at emission, so a subclass declared
  in a later unit (`TForm1 = class(TForm)`) inherits ancestor overrides.
- A class is registered for RTTI if it *or an ancestor* has published members.

The dropped `test/gui/helloworld` final mile landed: virtual
`TComponent.Create(AOwner)`, `Application.CreateForm`, named `class of`
metaclasses with runtime `ClassName`, `Dialogs.ShowMessage`, LCL unit stubs,
`{$R *.lfm}` wildcard handling, and streamed-child → published-field wiring.
The earlier plan remains as historical context in
[`handover-final-mile.md`](handover-final-mile.md).

---

## 2c. Import C headers for complex libraries  🟡  (active arc — the real goal)

Full phased plan: **[`plan-c-header-import.md`](plan-c-header-import.md)**.

**Progress (2026-06-01):**
- ✅ Pillar 1 (partial): DT_NEEDED deduplicated (one per distinct library, not
  per symbol); versioned soname table for libc/libm/libpthread/libdl/librt/libz
  replacing the `lib<name>.so` guess. Dynamic `ld.so.cache`/`DT_SONAME` probe
  deferred — the self-hosted compiler has **no execve**, so pkg-config/ldconfig
  shelling is impossible; the probe must read `/etc/ld.so.cache` or `.so`
  `DT_SONAME` via file I/O.
- ✅ Stage A: real C type model — widths, signedness, `void`, and pointers are
  preserved (`ParseCDeclType`). Regression `test/test_c_widths.pas`.
- ✅ Stage B (core): typedef (scalar/pointer/opaque struct+union), enum
  constants with a small const-expr evaluator, and function-pointer typedefs
  (as opaque pointers). Full struct field layout deferred per plan. Regressions
  `test/test_c_typedef.pas`, `test/test_c_enum.pas`.
- ✅ SysV float C-call ABI: float args in xmm0..7, int args in the six
  integer regs (independent classing), float return via xmm0. libm works.
  Regression `test/test_c_float.pas`. External calls only; internal Pascal
  convention unchanged.
- ✅ Argument stack spill: >6 integer / >8 vector args spill to the stack
  (SysV, 16-byte aligned). Required fixing a hardcoded `TProc` record layout
  (Params reserved too little space; 9+ param functions corrupted the next
  proc — latent self-host bug). Regression `test/test_c_argspill.pas`.
- ⬜ Remaining: Stage C macro soup (gtk), Stage D recovery, Stage E final
  wiring.


Direct Pascal `external 'soname'` binding (used for the GTK widgetset) is a
**stopgap, not the destination.** Hand-written bindings like `test/gui/gtk3.pas`
hardcode the soname (`libgtk-3.so.0`) and every prototype — manual versioning
and guaranteed drift against the installed library. The intended end state is
to **import the real C headers** (as `uses gtk3` already does for simple
headers like `ctype`), so we never re-declare externals by hand and the soname
follows the headers instead of being pinned.

The blocker is C's macro-heavy headers: GTK/glib pull in large macro and
typedef trees the current C importer (`cparser.inc`/`cpreproc.inc`) can't yet
digest. That is the hard part — not a reason to drop the goal.

- Strengthen the C preprocessor + parser enough to ingest glib/GTK-grade
  headers (nested includes, function-like macros, `typedef`/struct/enum/
  pointer churn, attribute spellings, conditional platform blocks).
- Then a binding becomes `uses gtk;` resolving `/usr/include/gtk-3.0/...` with
  the soname derived from the header set — no hardcoded version.
- Manual `external` stays available as the escape hatch for symbols not
  cleanly expressible from headers.

---

## 2d. Managed runtime values and thread audit  ⬜  (next runtime arc)

Full ordered design: **[`threads-todo.md`](threads-todo.md)**.
Dynamic-array continuation checklist:
**[`todo-dynamic-arrays.md`](todo-dynamic-arrays.md)**.

- Unify class, string, array, and raw-memory allocation behind one heap path;
  keep Linux syscalls as optional target hooks and improve
  splitting/coalescing/in-place resize/bins only after the shared path is
  correct. See
  **[`allocator-platform-design.md`](allocator-platform-design.md)**.
- Add a fixed-static-arena profile so allocator and managed-value tests pass
  without `mmap`, `munmap`, or `brk`.
- Finish the opt-in `{$define PXX_MANAGED_STRING}` migration. Heap-backed,
  reference-counted, copy-on-write strings, local cleanup, concatenation,
  coercions, and `SetLength` work; params/results, globals, exceptions, and
  remaining record/class ownership paths are pending.
- Dynamic arrays now cover scalar arrays, `array of AnsiString`, arrays of
  recursively managed records, params/results, whole-record managed assignment,
  embedded static-array field indexing, and nested arrays of scalar or managed
  bases. Deferred semantics: nested-level copy-on-write, exception-path cleanup,
  and fresh-result move semantics.
- Preserve a short default path: mutexes, spinlocks, and atomic updates are
  emitted only with `--threadsafe` / `{$THREADSAFE ON}`.
- Audit compound runtime operations after managed values land. In particular,
  threaded `write`/`writeln` needs statement-level serialization because one
  Pascal output statement currently emits several syscalls.

---

## 3. Interfaces  ⬜  (intentionally deferred)

Interfaces remain a real language gap, but they are not active work. No
current target source requires them, and even a lightweight Linux-native
model adds substantial dispatch, ABI, and lifetime-design surface. Revisit
when a concrete compatibility target needs them. The scoping outline below
keeps that future decision explicit.

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

- ✅ **General pointer syntax.** Typed-pointer path (Phase 2 unblock) done:
  - ✅ C1 named pointer aliases `PFoo = ^TFoo` (carry element type).
  - ✅ C2 pointer indexing `p[i]` read+write, stride = element size.
  - ✅ C3 record-pointer field access `p^.field` (deref a `^TRec` then field).
    Test: `test/test_ptr_deref_field.pas`.
  - ✅ C4 pointer casts `PType(expr)` preserving element type. `AN_PTR_CAST`;
    indexing a cast strides by the cast's pointed-at element size
    (`test/test_ptr_cast.pas`).
  - ✅ C5 scaled pointer arithmetic `p + n`, `p - n`, and `n + p`, including
    typed pointer fields, record pointers, and casts. Untyped pointers use byte
    stride. Test: `test/test_ptr_arithmetic.pas`.
  - `@var` address-of works for `@arr[i]`/`@x`.
  See [`pascal-gap-analysis.md`](pascal-gap-analysis.md) §1.3.
- ⬜ **Float intrinsics.** `Trunc`, `Round`, `Int`, `Float` not implemented
  (float arithmetic/compare/write itself is done).
- 🟡 **Managed `AnsiString` representation.** The opt-in
  `{$define PXX_MANAGED_STRING}` path implements heap-backed reference counts,
  local cleanup, copy-on-write indexed writes, concatenation, coercions, and
  `SetLength`. Complete params/results, globals, exception paths, and remaining
  record/class ownership before making it the default. Atomic refcounts protect
  lifetime accounting only; concurrent mutation and copy-on-write uniqueness
  checks still require external synchronization.
- 🟡 **Dynamic arrays.** Scalar, opt-in managed-string, recursively managed
  record, and nested elements support
  pointer-sized slots, assignment retain/release, indexed-write copy-on-write,
  preserving grow/shrink, zero-initialized new slots, `SetLength(a, 0)`
  reclaim, local-slot initialization and normal scope-exit release, and
  conditional atomic refcounts under `--threadsafe`. Deferred: nested-level
  copy-on-write, exception-path cleanup, and fresh-result move semantics.
- 🟡 **Heap allocator.** `GetMem`/`FreeMem` now do real free-list reuse on the
  IR backend (8-byte size header per block + single free list, first-fit, no
  split/coalesce). Enough that
  alloc/free-heavy programs reuse memory instead of only ever bumping.
  `New`/`Dispose`/`ReallocMem` also implemented on top of the same header
  (ReallocMem preserves `min(old,new)` bytes; IR backend only).
  **Proper allocator still TODO** (own arc): a syscall-free internal heap with
  alignment, splitting, coalescing, and in-place resize attempts, plus optional
  target hooks for region reserve/release/resize. Linux can use `mmap`/`munmap`
  hooks for large regions; bare-metal and RTOS-backed ESP32 profiles must not
  depend on them. Add bins after the shared allocator path is correct. See
  [`allocator-platform-design.md`](allocator-platform-design.md).
- ✅ **`Val`/`Str`** (integer). Implemented as pure-Pascal `lib/rtl/builtin.pas`
  (`StrInt`, `Val`), auto-included **only** when a program calls `Str(`/`Val(`
  (token pre-scan in ParseProgram, mirroring the exception-runtime prescan — no
  DCE, so always-including would bloat every binary). `Str(x[:w[:d]], s)` is
  rewritten by the parser to `s := StrInt(x, w)` (decimals parsed, ignored);
  `Val(s, n, code)` is a plain var-param call. Tests: `test/test_str_val.pas`.
  Gaps: float `Str`/`Val` (only Int64), and `:w:d` widths are literals not
  expressions (matches `write`).
  - **Overloading**: `Val` is a plain proc → add a `Double` overload in
    `builtin.pas` and the resolver picks by the destination's type, no special
    work. `Str` is parser-intercepted → the desugar dispatches on the value's
    `ASTTk` (float → `StrFloat`, else `StrInt`). ~free once float lands.
  - **Float conversion** (deferred): reuse what already exists rather than
    rolling new — the native float parser `StrToDoubleBits` (lexer.inc) for
    float `Val`, and the `writeln` float formatter for float `Str`. If importing
    from the system instead, the headers are `stdlib.h` (`strtod`, clean
    non-variadic) and `stdio.h` (`snprintf`, variadic → hard); **not** `math.h`
    (that's `sin/cos/pow`). Don't block on the C-header arc.
- ⬜ **`flexcolumn` calling-convention directive** (future). Generalize the
  `value:w:d` micro-grammar (today special-cased in `write`/`writeln`/`Str`)
  into a declarable directive, so formatted routines can be ordinary library
  functions whose call args carry optional `:w:d` modifiers. Pays off when
  `write`/`writeln` (variadic) move to library code; spec the per-arg
  modifier→formal mapping + variadic interplay then. Handle in the **parser**
  (it resolves the callee's directive), never the lexer. Rationale in the
  Str/Val discussion — see `plan-pascal-syntax-issues.md` §B1.
- ✅ **Name resolution / case sensitivity.** Implemented as a **per-origin case
  mode, never a global lower-pile** (matters for the multi-language /
  "frankenstein" goal: don't throw C/Pascal/BASIC symbols on one pile and lower
  them):
  - Each symbol is tagged with a case mode. C imports → always sensitive (the
    link symbol is exact). Pascal declarations → driven by a
    `{$CASESENSITIVE ON/OFF}` switch, **default off** for `.pas`. `ON` is an
    opt-in strict mode (typo-catching, verifying our own source). Each future
    frontend tags its own symbols' mode.
  - **Store names verbatim — never lowercase the symbol table** (lowercasing
    mangles C symbols and diagnostics). Match with the existing `CaseEqual`
    (`defs.inc:776`); `LowerCase` (`parser.inc:4899`, ASCII) already exists and
    is only needed if symbols later move to hashed lookup.
  - **Lookup = exact-first, then case-insensitive fallback** when no exact hit
    and the candidate is insensitive. C symbols stay exact-only.
  - ⬜ **Suggested: `{$LAZYCASING ON/OFF}` for C imports only** (deferred,
    default off). After exact lookup fails, allow a case-insensitive C-import
    fallback only when exactly one imported symbol matches. Preserve the
    declaration's exact spelling for ELF linkage. Reject ambiguous matches.
    This is a compatibility convenience for imported APIs, not a Pascal mode;
    it should not weaken `{$CASESENSITIVE ON}` Pascal code. Add warnings support
    before implementing so accepted spelling mistakes are visible.
  - ✅ Qualified `UnitName.Symbol` lookup resolves imported-unit symbols and
    overloaded routine calls. Test: `test/test_qualified_units.pas`.
  - A unit-rename import remains missing. `uses X as Y` is **not** standard Pascal
    (that's C#/Python `as`); Delphi has `uses U in 'file'` + dotted namespaces
    but no rename-import — a rename would be a dialect extension.
  - Unicode is out of scope for identifiers (Pascal/C identifiers are ASCII;
    existing ASCII folding suffices). Unicode is a string-data concern, separate.
  Discovered while wiring Str→StrInt (see [[project_rtl_dialect_landmines]]).
- ✅ **Enums.** Type identity + ordinal↔name infra in place and used by RTTI
  (enum prop kind, EnumRTTI).
- ✅ **Set algebra / comparison.** Dedicated 32-byte IR operations cover copy
  assignment, union, intersection, difference, equality, and subset/superset
  comparisons. Set literals, named set types, `in`, nested algebra, and
  RTTI-backed set properties remain covered. Locals, record fields, `var`
  params, and by-value reads are covered by `test/test_set_shapes.pas`.
  Set-valued and record-valued function results use the shared hidden-
  destination aggregate-return ABI; see `test/test_aggregate_results.pas`.
- ✅ **Explicit `inherited` calls.** Parent-chain static dispatch works for
  constructors, methods, bare `inherited`, and inherited function results.
  Test: `test/test_inherited.pas`.
- 🟡 **Generics.** Template mechanism exists; breadth vs FPC unverified.
- ✅ **Class visibility.** Phase 0 of the LFM arc done (see §2).
- ✅ **Method-call-with-args as a statement.** Rechecked 2026-05-31 with a
  direct `o.SetV(42)` statement; it compiles and updates the field correctly.
  The earlier TODO was stale.
- ✅ **Comments.** Nested `{ }` / `(* *)` under `{$NESTEDCOMMENTS ON}`, C-style
  `/* */` under `{$CSTYLECOMMENTS ON}` (both default off, TP/Delphi-compatible),
  and `(* *)` followed by same-line code fixed unconditionally. Done 2026-05-31
  (commit 6525e95); see [`plan-pascal-syntax-issues.md`](plan-pascal-syntax-issues.md)
  §A. The compiler source opts into nested comments at its top; keep comments
  simple anyway because bootstrap recovery may involve older seeds.
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

- ✅ **`shl` operator.** Tokenised and lowered through the IR alongside `shr`.
  Test: `test/test_shl.pas`.
- ✅ **`readln` / `read` statements** — implemented 2026-05-30 (user-requested).
  `readln(targets...)` reads one line from stdin into a BSS line buffer
  (`EmitReadLine`, byte-at-a-time, stops at `\n`, skips `\r`) and parses each
  lvalue by type (`EmitReadVarParse`): integer (leading blanks skipped, optional
  `-`), several ints from one line, whole-line string, single char; bare
  `readln` skips a line. AST `AN_READLN`/`AN_READ` → IR `IR_READLINE` +
  `IR_READ_VAR`. `read` currently behaves like `readln` (reads a fresh line —
  does not yet preserve the remainder of a line across calls). Test:
  `test/test_readln.pas`.
- ✅ **Named result in a class method** — fixed 2026-05-30. `Bar := v` inside
  `function TFoo.Bar` now hits the result slot. The statement-level result-assign
  check only matched `Procs[].Name`, which for a method is `TFoo.Bar`, so the
  bare `Bar` fell through to a self method-call. Fix (`parser.inc` ~3100): also
  match the method short name via `LastDotName`, gated on a `:=` lookahead (so a
  recursive call statement isn't mistaken for an assignment).
  Test: `test/test_method_named_result.pas`.
- ✅ **Indexing a pointer-typed class field** — fixed 2026-05-30. `FField[i]`
  (read + write) now dereferences the pointer with the right element stride.
  Added an `AN_FIELD` pointer-index fast path in `IRLowerAddress` plus
  `RecFieldPtrElemTk`/`RecFieldPtrElemRec` accessors over `UFldPtrElem*`.
  Test: `test/test_ptr_field_index.pas`.
- ✅ **Multi-name record/class fields** — fixed 2026-05-30. `X, Y: Integer` in a
  `record`/`class` now declares both (each at its own offset); the field parser
  only read one name before `:`. Also fixed `ResolveNodeRec` for indexing a
  pointer-to-record field then a `.field` (`c.Pts[i].X`): two `FindUField` calls
  were missing the `- REC_UCLASS_BASE` class-index offset, and the parser suffix
  loop didn't carry the element record for an `AN_FIELD` pointer base.
  Test: `test/test_record_multifield.pas`. (The earlier "chained `[i].field`"
  note was a misdiagnosis — the real blocker was the multi-name field parse.)
- ✅ **Single-char string literal / char → string** — fixed 2026-05-30. See the
  "char → string coercion" entry in §1.2 above. `s := 'x'`, `s := someChar`,
  `s := Chr(n)`, and char→string class/record fields all work now.
- ✅ **Whole-record copy truncated records > 8 bytes** — fixed 2026-05-30.
  `r1 := r2` and `arr[i] := arr[j]` copied a hardcoded `TypeSize(tyRecord)` = 8
  bytes (one qword) regardless of the record's real size, so anything larger
  (e.g. the 16-byte `TFixup`, or any user record with >2 ints) lost its tail.
  The earlier "main-program body / heisenbug" framing was wrong: the trigger is
  simply record size > 8 (compiler.pas's `Fixups`/`TFixup` is 16 via the
  hardcoded `RecSize` table, so the sentinel-drop shift truncated it → NULL
  string literals). Fix: whole-record lvalue assignment now lowers to
  `IR_COPY_REC` (rep movsb of the full `RecSize`) instead of the scalar
  qword store. The field-wise workaround in `compiler.pas` was removed.
  Test: `test/test_record_copy.pas`.
- Note: "integer-only compiler tables" stays a deliberate **constraint**, not a
  bug — it is the fixedpoint-safety convention, nothing to fix.

### Recently resolved (corrects stale notes in gap-analysis / older memory)

- ✅ `break` / `continue` — implemented (`parser.inc` ~2687/2693).
- ✅ Sets (`set of T`, literals, `in`, algebra, comparisons) — implemented.
- ✅ `with` statement — implemented.
- ✅ Floating point (Single/Double/Extended, arithmetic, compare, Write) —
  implemented, IR parity done.
- ✅ Inline assembler (rudimentary) — see [`inline-asm.md`](inline-asm.md).

---

## 5. Backend & targets

- ✅ **Delete the frozen direct backend.** Retired from the active compiler on
  2026-05-31. Archived as `historic/direct-codegen-legacy.inc`; shared
  exception-runtime emission moved to `compiler/exception_emit.inc`.
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

- IR backend only. The retired direct emitter is historic reference material.
- Self-host constraints: avoid string `+` on hot paths (use `AppendChar`);
  initialize strings via `''` + `AppendChar`; keep compiler-side tables
  integer-only for fixedpoint safety.
- Validate with `make bootstrap` (fixedpoint) **and** by running each feature's
  regression test under the self-built compiler — fixedpoint alone is not
  correctness.
- Commit per logical unit; never push without explicit confirmation.

---

## Note on `pascal-gap-analysis.md`

That document is **partially superseded**: it lists sets/floats as gaps (now
done) and parks interfaces "indefinitely" (now planned — see §3). Treat this
TODO and the linked plans as current; refresh the gap analysis when convenient.
