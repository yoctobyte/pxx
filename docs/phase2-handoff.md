# Phase 2 Handoff — RTTI reflection via typed pointers

Session handoff for the LFM-enablement arc (plan: `plan-rtti-streaming-lfm.md`;
ordered TODO: `todo.md` §2 Phase 2 + §4 pointer gap). Read those first — this
file is the *resume checklist*, not the spec.

## Done + committed (fixedpoint green throughout)

- **Phase 0 ✅** class visibility parsing (`private/protected/public/published`,
  not enforced). Per-member published flag: `UFldPub`/`UMthPub`/`UPropPub`
  (integer-only, per the fixedpoint-safety convention). Test:
  `test/test_visibility.pas`.
- **Phase 1 🟡 (core)** RTTI emission — `compiler/rtti_emit.inc`:
  - Blob layout = OUR own, `RTTI_*` constants in `defs.inc`.
  - `AddDataPtrFix` = data→data 8-byte pointer relocation (applied in BOTH
    `writeELF` variants in `elfwriter.inc`, next to the `MethodFixups` loop).
    Code-address slots (method/proc) reuse `MethodFixups`.
  - name→RTTI registry (`RTTIRegistryOff`/`RTTIRegistryCount`).
  - `--dump-rtti` prints the built structure (compile-time verification).
  - Kinds covered: **integer/ordinal, string, class, enum.** Enum needed new
    type-identity infra (was: enum dissolved into int consts): `EnumType*`/
    `EnumVal*` tables, `LastTypeEnumId`, `UPropEnumId`, `EmitEnumRTTI`.
  - **Reserved/deferred kinds:** set, method-pointer (events).
  - Test: `test/test_rtti_emit.pas` (parent/child, int/string/class/enum props,
    published method) — runtime check + `--dump-rtti` greps in `make test`.
- **Phase 2 🟡 (started)** — chosen unblock = **fix general typed pointers**
  (decision below). Steps done:
  - **C1 ✅** named pointer aliases `PFoo = ^TFoo`. `Alias*` table in `defs.inc`,
    `RegisterPtrAlias`/`FindTypeAlias` in `symtab.inc`, registration branch in
    `ParseTypeSection`, resolution in `ParseTypeKind` (sets
    `LastTypePointerElem*`, which `AllocVar` already propagates).
  - **C2 ✅** pointer indexing `p[i]` read+write. Pointer-base branch in
    `IRLowerAddress` (`ir.inc` ~296): base = pointer VALUE (not `&p`), stride =
    pointed-at element size; parser types `p[i]` as the element type.
  - **C3 ✅** `p^.field` (record-pointer field access). The `AN_FIELD` branch of
    `IRLowerAddress` combined with `ResolveNodeRec(AN_DEREF(...))` already
    threaded correctly — no compiler change needed.
  - Tests: `test/test_ptr_alias.pas`, `test/test_ptr_deref_field.pas`.

## Why typed pointers (not asm helpers / codegen intrinsics)

Architect decision. Every Phase 2 op needs computed-address memory access +
call-through-register. At the fork:
- Pure Pascal: `p^` worked; `p+n` arithmetic and `p[i]` indexing were broken
  (garbage). C1/C2 fixed the indexing path.
- Inline asm: no `[reg+disp]` operands, no `call reg`, and **no relocation in
  the parse-time asm buffer** — so it can't even reach the registry address.
  Disqualified for this.

Typed pointers are the most Pascal-native and retire the `todo.md` §4 pointer
gap as a side effect.

## Resume checklist (ordered)

1. **C3 ✅ — `p^.field` (record-pointer fields).** Deref a `^TRec` then access
   a field. The IR path in `IRLowerAddress` already threaded correctly: the
   `AN_DEREF` branch returns the pointer value as the base address, and
   `ResolveNodeRec(AN_DEREF(...))` yields the pointee's record ID for offset
   lookup. No compiler change was needed — the feature was already wired;
   the test confirms correctness. Test: `test/test_ptr_deref_field.pas`.
2. **C4 — pointer casts `PType(addr)`.** Turn an `Int64`/`Pointer` address into
   a typed pointer. Currently errors `undefined variable (PType)` because casts
   parse as function calls — needs cast recognition for alias type names.
3. **Registry access.** Runtime Pascal needs the address of the registry blob.
   `RTTIRegistryOff` is only known *after* parse (RTTI emitted post-parse), so a
   finalize-time fixup is required — model it on `EmitDataRef` (which patches
   `dataBase + DataOff` at link). Likely a tiny codegen intrinsic `__rttireg`
   returning the address, or a fixed head symbol. **Asm cannot** (no reloc in
   its buffer).
4. **Indirect call** — only for method-backed props + events
   (`GetMethodAddr`/`SetMethodProp`). Needs procedural-variable call or an IR
   `call_indirect`. **Field-backed props — the common streaming case — do NOT
   need it; deliver those first.**
5. **`typinfo.pas`** — `GetClass`/`GetPropInfo`/`GetPropList`/`Get|SetOrdProp`/
   `Get|SetStrProp` over the emitted blobs (TypInfo names). Round-trip test
   `test/test_rtti.pas` under the self-built compiler.

## Self-host gaps surfaced this arc (logged in `todo.md` §4)

All ⬜ unless noted. Masked by bootstrap because the compiler doesn't use them
on itself — same class as the op-overload/string-`+` bugs:
- `shl` operator (no `tkShl`; only `shr`).
- `readln`/`read` statements (lexed, never parsed).
- single-char literal `'x'` typed as `tyChar` (forces `s:=''`+`AppendChar`).
- method-call-with-args as a statement (`obj.M(arg);` fails; no-arg works).
- nested `{ }` comments (self-hosted lexer ends at first `}`; FPC nests). Avoid
  inner braces in compiler-side comments.
- 🔴 string field on a class reads/writes garbage (record string fields work —
  see `record_string_field.pas`). **Blocks streaming string props** until fixed.

## Working rules (reminders)

- IR backend only; `codegen.inc` frozen. Validate with `make bootstrap`
  (fixedpoint) **and** the feature's regression test run under the self-built
  compiler. `make test` dies at `test_op_overload.pas` (pre-existing IR red) —
  run targeted tests past it.
- No `shl` in compiler-side code (use `*2^n`); build strings via `AppendChar`;
  keep new compiler tables integer-only.
- Commit per logical unit; never push without explicit confirmation.
