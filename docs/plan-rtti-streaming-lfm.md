# Implementation Plan: RTTI → Published → Streaming → Resources → LFM

Agent-executable plan for the Lazarus/LCL enablement arc. Decomposed so
separate agents can take individual tasks. Each task lists goal, files,
dependencies, approach, and done-criteria. **Read the cross-cutting rules
first — they apply to every task.**

Authoritative source is the code and the regression tests; this plan is the
intended shape, not a contract.

## Locked decisions (2026-05-29)

- **RTTI: custom-minimal, TypInfo-named.** Our own table layout, sized to
  exactly what streaming needs. Public reflection API uses the *names* from
  `System.TypInfo` (`GetPropInfo`, `GetPropList`, `GetOrdProp`, `SetOrdProp`,
  `GetStrProp`, `SetStrProp`, `GetMethodProp`, `SetMethodProp`) so a later
  FPC-binary-compat port is mechanical. **Do not** replicate FPC's binary
  `TTypeData` layout now.
- **Streaming: minimal own TReader/TWriter.** A small filer that walks the
  binary form stream and sets published properties via our RTTI. Mirror FPC
  semantics, not its `classes.pp` source.
- **RTTI breadth: published-only, streaming-grade.** Cover property kinds:
  integer/ordinal, enum, set, string, class, and method-pointer (events).
  General `TypeInfo(T)`-for-everything is out of scope here.
- **Scope: stops at LFM.** Phases 0–5 below. Interfaces are a stub (see end),
  planned separately; they are **not** a streaming prerequisite.
- **GUI is out of scope.** Deliverable is "instantiate a component tree from
  an `.lfm`", not "draw a window". Actual LCL widget sets are pure library
  work afterward, with no further compiler ask.

## Cross-cutting rules (EVERY task)

1. **IR backend only.** `codegen.inc` (direct) is frozen/reference — do not
   add features to it. New emission goes in `symtab.inc` / `ir.inc` /
   `ir_codegen.inc`. IR is the default and bootstraps the compiler.
2. **Self-host constraints** (the compiler must compile this code):
   - No `shl` operator — use `* 2^n`. (`shr` is fine.)
   - No string `+` on hot paths — build strings with `AppendChar`. (`+` in
     `Error(...)` is tolerated; those paths abort.)
   - Initialise strings as `s := ''` then `AppendChar`, not single-char
     literals (single-char literals are `tyChar`).
   - Keep new compiler-side tables **integer-only** (offsets/indices into
     shared arrays), matching the existing `UCls*/UFld*/UMth*` convention —
     "integer-only for fixedpoint safety".
3. **Validation discipline.** Fixedpoint (`make bootstrap`, gen2==gen3) is
   necessary but **not sufficient** — it does not exercise features the
   compiler doesn't use on itself (this is exactly how the op-overload and
   string=char bugs hid). For every task: `make bootstrap` **and** build the
   feature's regression test **with the self-built compiler** and check its
   runtime output. Add the test to `make test`.
4. **Write code as proto-units.** Cohesive, minimal reach-through into other
   files' globals, a clear "provides / needs". This is the cheap tax that
   makes the eventual `.inc → .pas unit` split mechanical. RTL pieces (typinfo,
   streaming, lfm) should be written as real `.pas` units from the start where
   practical — the inline-unit model already supports `uses`.
5. **Commit per logical unit; never push without explicit confirmation.**
6. **Known standing red:** `test/test_op_overload.pas` segfaults under IR
   (pre-existing, unrelated). `make test` dies there. Don't be alarmed; run
   targeted tests, don't treat the full-suite red as your regression.

## Current state (verified 2026-05-29)

- Classes carry fields (`UFld*`), methods with VMT/virtual slots (`UMth*`,
  `UClsVMTOffset`, `UClsVirtCount`), and **properties** (`UProp*`: name, type,
  read/write field or method). Class body parsed in `ParseTypeSection`
  (`parser.inc` ~3333).
- **No visibility parsing.** `private/protected/public/published` in a class
  body currently misparse (treated as a field name). Phase 0 fixes this.
- VMT dispatch + method-address fixups exist (`MethodFixups`, patched at
  finalize) — reuse this pattern for RTTI method-address slots.
- Constructors work (`TFoo.Create` → allocate + run constructor).
- Inline asm now exists (`docs/inline-asm.md`) — useful for the indirect
  method-call thunk in Phase 2.

---

## Phase 0 — Class visibility parsing  (prereq, small)

**Goal.** Recognise `private/protected/public/published` section markers in a
class body; tag each member with a `published` flag. Do **not** enforce access
(private is intentionally not enforced — see project policy).

**Files.** `parser.inc` (class-body loop ~3333), `defs.inc` (new flag arrays),
`compiler.pas` (reset).

**Approach.**
- Add `UFldPub`, `UMthPub`, `UPropPub : array[...] of Boolean` (or pack into an
  existing int as a visibility code 0..3 if you prefer one field; boolean is
  enough for streaming).
- In the class-body loop, before the method/property/field branches: if
  `CurTok` is an ident case-equal to one of the four markers, set a local
  `curPublished := CaseEqual(sval,'published')`, `Next`, `continue`.
- Members parsed while `curPublished` → set the member's Pub flag at
  `AddUField/AddUMeth` (extend those to take/record the flag, or set the array
  slot right after the Add).
- Default (members before any marker): treat as **not published** (opt-in).
  Document this; revisit only if a real form needs default-published.

**Done.** A class with all four sections parses; members tagged correctly.
Existing class tests pass; fixedpoint holds. Add `test/test_visibility.pas`
that declares sections and exercises a published vs non-published member.

---

## Phase 1 — RTTI emission (published-only)

**Goal.** For each class with ≥1 published member, emit a compile-time RTTI
blob and register it by class name so streaming can find it.

**Files.** new `rtti_emit.inc` (compiler-side emission; keep cohesive),
`symtab.inc` (finalize-time pointer/code fixups), `defs.inc` (fixup lists),
`elfwriter.inc` only if a dedicated section is wanted (not required — `.data`
is fine).

**RTTI blob layout (OUR layout — keep it simple, integer fields, pointers via
DataRef/code fixups).** Per class:
```
ClassRTTI:
  name            -> ptr to length-prefixed string
  parentRTTI      -> ptr to parent ClassRTTI (or 0)
  instanceSize    : int        { = UClsSize_ }
  vmtPtr          -> class VMT  { for instantiation }
  propCount       : int
  props           : array[propCount] of PropInfo
  methCount       : int        { published methods, for event binding }
  meths           : array[methCount] of MethInfo

PropInfo:
  name            -> string
  kind            : int        { piInteger, piEnum, piSet, piString, piClass, piMethod }
  typeRef         -> RTTI of the prop's type (enum/class) or 0
  getKind         : int        { 0=field, 1=method }
  getRef          : int/ptr    { field offset, or method code ptr }
  setKind         : int
  setRef          : int/ptr
  ordType         : int        { for ordinals: signed/size hint }

MethInfo:
  name            -> string
  code            -> proc code address   { resolved via a fixup list }
```

**Approach.**
- Allocate blobs in `Data[]` via the existing data emission; record string
  pointers with `EmitDataRef`, parent/type pointers with data fixups, and
  **method/proc code addresses with a new fixup list** patched at finalize —
  copy the `MethodFixups` mechanism (it already patches proc addresses into the
  VMT after codegen).
- Build a **class registry**: a global table (name → ClassRTTI ptr) plus a way
  to instantiate (vmtPtr + instanceSize already in the blob). This backs
  `GetClass(name)` and `TReader` instantiation. Emit it as data + a head
  symbol the RTL can read.
- Enum RTTI: a type needs an ordinal↔name table. **Verify enum support first**
  (`grep` for enum type handling); if enums are thin, this is a sub-task —
  emit `{ count, array of name ptrs }` keyed by the enum type.

**Risks / verify.**
- Enum type support may be incomplete — confirm and size accordingly.
- String representation is length-prefixed (`Strs[i].Offset` = 8-byte length
  prefix, bytes at +8). RTTI name strings must match what the RTL string ops
  expect.

**Done.** A compiled program can, via a temporary debug dump or the Phase 2
API, enumerate a class's published props/methods with correct names, kinds,
offsets, and (post-link) correct method addresses. Fixedpoint holds.

---

## Phase 2 — Reflection API (TypInfo-named)  — mostly RTL, some intrinsics

**Goal.** Pascal-callable reflection over the Phase 1 RTTI, with TypInfo names.

**Files.** new RTL unit `typinfo.pas` (compiled like a user unit via `uses`);
possibly one compiler intrinsic for indirect calls.

**API (minimum).**
```
function GetClass(const name): PClassRTTI;
function GetPropInfo(cls: PClassRTTI; const name): PPropInfo;
function GetPropList(cls: PClassRTTI; out list): Integer;
function GetOrdProp(instance: Pointer; p: PPropInfo): Int64;
procedure SetOrdProp(instance: Pointer; p: PPropInfo; v: Int64);
function GetStrProp(instance: Pointer; p: PPropInfo): string;
procedure SetStrProp(instance: Pointer; p: PPropInfo; const v: string);
function GetMethodAddr(cls: PClassRTTI; const name): Pointer; { event binding }
procedure SetMethodProp(instance: Pointer; p: PPropInfo; code: Pointer);
{ set/get for set-typed props as ord }
```
**Approach.**
- Field-backed props: read/write `instance^ + fieldOffset` at the right width.
- Method-backed props: **indirect call** `method(instance, value)` /
  `:= method(instance)`. We have no generic "call code ptr with args" yet —
  implement a small thunk. **Inline asm is the clean tool here** (load args to
  rdi/rsi, `call rax`). One asm helper per arity needed (0/1 arg covers
  ord/str getters/setters). Alternatively add an IR `call_indirect` op.
- Cast/pointer arithmetic must be expressible — verify the language supports
  enough (`Pointer`, typed deref, offset add). If not, that's a sub-task or an
  asm helper.

**Done.** `test/test_rtti.pas`: build a class with published Integer + String
+ enum props, then Get/Set each via the API and assert round-trip. Runs under
the self-built compiler.

---

## Phase 3 — Streaming runtime (TReader-lite)

**Goal.** Read a **binary** form stream and instantiate + configure a component
tree using Phase 2.

**Files.** new RTL units: `streams.pas` (memory stream over a byte blob),
`classes_lite.pas` (TComponent-lite base + TReader).

**Binary form (Delphi/LCL filer) format — summary.**
- Signature `'TPF0'`.
- Then a component: prefix byte (flags: child/inherited), `ClassName` (string),
  `Name` (string), then a **property list**: repeated `{ PropName(string),
  ValueType(byte), Value }` until a `0` terminator byte, then nested child
  components until a `0` terminator, then end.
- ValueType bytes (`vaInt8/vaInt16/vaInt32/vaInt64`, `vaString/vaLString`,
  `vaIdent` (enum/identifier), `vaSet`, `vaTrue/vaFalse`, `vaNull`, ...).
  Implement the subset forms emit needs; error clearly on unsupported.
- Document the exact byte grammar in this file or a sibling doc as you
  implement (reference: Delphi TFiler/TReader binary format).

**Approach.**
- `TReader.ReadRootComponent(root)`: read signature; read the root record;
  set root's published props via Phase 2; for each child: read class name →
  `GetClass` → instantiate (vmtPtr + instanceSize from RTTI, run constructor) →
  set `Name` → set props → recurse.
- Property dispatch: map ValueType byte → which `Set*Prop` to call, resolving
  the PropInfo by name on the component's class RTTI.
- Event props (`vaIdent` whose PropInfo.kind = piMethod): resolve the
  identifier as a published method **on the root** via `GetMethodAddr`, then
  `SetMethodProp`.
- Unknown property name or type → controlled error (don't silently skip during
  bring-up; skipping is a later compatibility nicety).

**Done.** `test/test_streaming.pas`: a hand-built binary stream (bytes in a
`db`/const array) describing a root with 2 props + 1 child with 1 prop and an
event; stream it into instances; assert all values + the event address. No GUI.
Runs under the self-built compiler.

---

## Phase 4 — Resource embedding primitive

**Goal.** Get an arbitrary file's bytes into the binary as a named, length-known
blob, with a runtime `FindResource`.

**Files.** `lexer.inc`/`parser.inc` (directive), `symtab.inc`/`elfwriter.inc`
(emit blob + resource table), RTL `resources.pas` (`FindResource`).

**Approach (own ELF strength — we control the writer).**
- Directive: accept `{$R name file}` (or a builtin `EmbedResource`). At parse
  time read the file, append its bytes to `.rodata`/`.data`, and append a
  record `{ nameptr, dataptr, len }` to a global resource table with a head
  symbol.
- Runtime `FindResource(name): pointer; out len`: linear-walk the table.
- Fallback worth noting: the Lazarus legacy `.lrs` path is *pure Pascal*
  (`LazarusResources.Add('name','type',[bytes])`) and needs **zero** compiler
  change — only the ability to compile a large `array of byte` const. Use it as
  a smoke test of large-blob handling before/instead of the ELF-section work.

**Risks.** Large blobs vs current data/const limits and alignment — verify the
const/data path handles size; watch the 64 KB-style fixed buffers.

**Done.** `test/test_resource.pas`: embed a small file, `FindResource` returns
correct bytes + length; assert byte-equal. Fixedpoint holds.

---

## Phase 5 — LFM library

**Goal.** End to end: `.lfm` text → embedded binary form → streamed component
tree. Almost entirely library; the only compiler dependency is Phase 4.

**Files.** toolchain program/unit `lfmconv.pas` (text→binary), RTL glue
(`InitInheritedComponent`-equivalent). No new compiler feature beyond Phase 4.

**Approach.**
- Build-time: `lfmconv` does `ObjectTextToBinary` — parse `.lfm` text
  (object/properties/nested/end grammar) and emit the Phase 3 binary form.
  Runs in the toolchain, not the target → no self-host constraint, but it must
  itself be compilable by us (so keep it simple Pascal).
- Embed the produced binary via Phase 4, named by the form's class.
- Runtime: a `TForm`-lite `Create` calls an `InitInheritedComponent` that does
  `FindResource(ClassName)` → `TReader.ReadRootComponent(self)`.

**Done.** `test/test_lfm.pas` + a tiny `.lfm`: a non-visual component tree with
a couple of properties and a child; after `Create`, assert the streamed values
on the instances. Still no GUI rendering — that's later library work.

---

## After this plan

- **GUI / LCL widget sets:** pure library work on top of Phase 5. No compiler
  ask. Abstracted widget sets per Lazarus design; out of scope here.
- **Interfaces (separate plan, future session):** the last big language
  feature. Will need `IInterface`/`IUnknown`, GUIDs, an interface method table
  (IMT) distinct from the class VMT, `as`/`Supports`, and a reference-counting
  decision (TInterfacedObject vs corba/no-refcount). **Not** required by
  streaming, so deliberately deferred. See `docs/limitations.md`.

## Suggested task ordering for parallel agents

- Phase 0 → Phase 1 are serial (RTTI needs visibility tags).
- Phase 2 depends on Phase 1.
- Phase 4 is **independent** — can be done in parallel with 0–2 (good warm-up /
  de-risk; proves the ELF-section + large-blob path early).
- Phase 3 depends on Phase 2.
- Phase 5 depends on Phase 3 + Phase 4.
