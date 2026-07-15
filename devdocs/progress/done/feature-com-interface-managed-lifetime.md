---
summary: "finish COM interface managed lifetime (refcount like ansistring): scope-exit / param / result / field release, then default {$interfaces com} (FPC parity); CORBA stays the lightweight opt-out"
type: feature
track: A
prio: 50
---

# COM interface managed lifetime — refcount an interface var like an ansistring

- **Type:** feature / correctness arc (interface ARC lowering + RTL). Fixes a
  **silent** RAII break (destructors never fire on scope exit).
- **Track:** A (IR/codegen of managed-type lifetime; shared RTL helpers).
- **Authorized:** user, 2026-07-15, after the COM-vs-CORBA design discussion.
- **Subsumes:** [[bug-a-interface-release-on-last-ref-not-destroyed]] (that bug is
  one symptom — the `it := nil` case already works; the missing piece is
  scope-exit / param / result / field finalization).

## Model (settled with the user)

pxx supports BOTH interface flavours, mode-switched, ZERO conflict — they already
have distinct IMT layouts and a per-interface `UClsIsComInterface` flag:

- **CORBA** (`{$interfaces corba}`) — lightweight: interface = pure polymorphism,
  no lifetime coupling, ANY class implements it, no reserved slots. Plain pointer
  copy on assign. This is pxx's current default and stays the opt-out.
- **COM** (`{$interfaces com}`, FPC/Delphi default) — **managed, exactly like an
  ansistring**: a COM interface var is a refcounted handle. `intf := other`
  AddRefs; `intf := nil` / reassign / **scope exit** Releases; the object's
  destructor runs when refcount hits 0 (NOT unconditionally — only the last ref
  frees, identical to `s := ''` freeing an ansistring buffer only at refcount 0).
  Derives IInterface (QI/_AddRef/_Release at IMT slots 0-2); implemented by a
  TInterfacedObject descendant.
- **GUID is orthogonal to COM-ness**: refcounting needs no GUID; the GUID is only
  the lookup key for runtime query (`as` / `QueryInterface` / `Supports`). A
  CORBA interface may carry a GUID (by-name/by-GUID lookup) and a COM interface
  without one is legal (just not queryable). So do NOT infer COM from a GUID (the
  rejected heuristic that broke `test_getinterface_guid_b257`).

## Current state (what exists / what's missing)

Exists (COM ~half-built, gated OFF behind `InterfacesComMode`):
- implicit IInterface parenting + the 3 reserved slots (COM vs CORBA IMT layouts
  already differ);
- RTL helpers `PXXIntfAddRefRaw` / `PXXIntfRelease` / `PXXIntfAssign`;
- retain-new / release-old on interface **assignment** (`ir.inc` ~4890-4975):
  `it := class`, `it := other`, `it := nil` all balanced.

Missing (the plumbing this ticket adds — mirror the ansistring managed-local
machinery, which already exists per-backend, e.g. `EmitAnsiStrReleaseLocked` /
`EmitAnsiStrReleaseForSym` and the store-time retain/release-old at
`ir_codegen.inc` IR_STORE_SYM tyAnsiString):

1. **Scope-exit release of a COM interface local** — a COM interface local going
   out of scope must `PXXIntfRelease` at the proc epilogue, exactly where an
   ansistring local is finalized. *Verified missing:* a `procedure Use; var it:
   IThing; begin it := TThing.Create; end;` leaks — no destructor. **Item 1, do
   first.** Entry point: find where ansistring/dynarray locals get their
   scope-exit release and add the `UClsIsComInterface` case (nil-init at prologue
   too, so an early exit / never-assigned local releases nothing garbage).
2. **Param / result rules** — AddRef a function's interface **result** before
   return (the caller owns the +1, like a returned ansistring); value-param
   retain-on-entry / release-on-exit; `const` interface param skips refcount.
3. **Field init/final** — a COM interface field in a record/class: nil-init on
   construction, release on finalize. `RecordHasManagedFields` already walks
   managed fields — include COM interfaces so the managed-record path covers them.
4. **Default flip** — default `{$interfaces com}` (FPC parity), CORBA behind the
   directive. Add `{$interfaces corba}` to the ~7 GUID-less CORBA-lenient tests
   (`test_interfaces`, `_as`/`_is`/`_inherit`/`_param`/`_multi_secondary`) — under
   real FPC they'd need it too. **DO THIS AFTER item 1** — flipping first would
   leak on every scope exit.
5. **`as` / `Supports` via QueryInterface** (optional, defer) — strict COM runtime
   query by GUID. pxx recovers the IMT from RTTI by id for calls; the QI protocol
   path is separate. Not needed for lifetime; pick up only if a corpus needs it.

## Sequencing

1 (scope-exit) → 2 (param/result) → 3 (fields) → **then** 4 (default flip). 5 last / optional.

## Acceptance

- `bug-a-interface-release-on-last-ref-not-destroyed`'s repro runs the destructor
  on scope exit (no explicit `:= nil`), and the multi-ref case (last ref frees,
  earlier drops don't) is correct — a `test/` regression pins refcount timing.
- Interface result / value-param / const-param / record-field lifetime match FPC.
- After the flip: `{$interfaces com}` default; the CORBA tests carry
  `{$interfaces corba}` and stay green; the FPC-valid interface corpora
  (fpcunit's TNoRefCountObject shape, fgl, etc.) compile and run.
- self-host byte-identical; cross targets green (per-backend epilogue release, like
  ansistring already has).

## Log
- 2026-07-15 — resolved, commit 3cd9f25a.

## Resolution (2026-07-15, agent-A)

Landed the COM managed-lifetime arc:

- **Item 1 (scope-exit release)** — already in tree from the prior session
  (bb286dfb): a COM interface local `_Release`s at the proc epilogue
  (`EmitManagedLocalCleanup`, `SymIsComInterface` case). Verified: scope-exit
  destructor + multi-ref timing (last ref frees, earlier drops don't).
- **Item 2 (param/result)** — commit 8a499a68. A by-value COM interface arg is
  marshalled through a private temp copy (anti-aliasing path) released at the
  caller's scope exit; it lacked a matching retain, so it double-dropped the
  caller's single reference (silent use-after-free once the value escaped to a
  global). Fixed: `PXXIntfAddRef` the temp after the `copy_rec`. `const` params
  stay by-ref aliases (no copy, no refcount); function results already AddRef.
  Regression: `test_interface_com_value_param`.
- **Item 3 (record fields)** — commit cb2ed843. COM interface fields of a value
  record are now managed: `RecordHasManagedFields`/`FieldIsManaged` recognise
  them, `EmitLayoutRTTI` emits descriptor member kind 4 (Interface, ifaceId in
  typeRef), `PXXRecordRetain`/`PXXRecordRelease` handle kind 4. Zero-init +
  copy-retain + scope-release. Regression: `test_interface_com_record_field`.
- **Item 4 (default flip)** — commit 3cd9f25a. Default is now `{$interfaces com}`
  (FPC parity); CORBA is `{$interfaces corba}`. Resolves the anchor bug in
  default mode. GUID-less CORBA-style tests carry the directive explicitly.
  Self-host byte-identical; native tier green (939/940, 1 unrelated skip).

### Remaining (filed separately — NOT part of this arc's acceptance)

- **Class-field finalization** — a COM interface field of a *class* (not a value
  record) is not released on `Free`, because pxx classes finalize NO managed
  fields at all (even an ansistring class field leaks on destruction). This is a
  broader pre-existing gap, not interface-specific → filed as
  [[bug-a-class-managed-fields-not-finalized-on-destroy]].
- **Item 5 (`as`/`Supports` via strict QI protocol)** — deferred as the ticket
  planned. `as`/`is`/`GetInterface` (GUID lookup via RTTI) already work; the
  strict COM QueryInterface protocol path is a separate optional enhancement, not
  needed for lifetime. Pick up only if a corpus requires it.
