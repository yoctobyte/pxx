# Managed aggregate locals on cross targets

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Unblocks:** feature-cross-bootstrap-selfhost
- **Opened:** 2026-06-13 (split out of feature-cross-codegen-gaps item 1 once it
  grew into a multi-part sub-arc)

## Motivation

A local whose managed extent exceeds a pointer — a **record with managed
fields**, a **variant**, or an **array of managed elements** — is not yet
supported on the cross targets (i386 / ARM32 / AArch64). It is the next arm32
`compiler.pas` cross-compile wall (parser line 13288,
`managed aggregate locals not yet supported`), so closing it is a gate for
feature-cross-bootstrap-selfhost. The scalar managed cases (AnsiString handle,
dyn-array handle) already work; this ticket is the larger-than-a-pointer case.

This is a **multi-part feature, not a one-spot fix** (investigated 2026-06-13 on
arm32; prototyped zero-init alone, which *compiles but crashes at runtime* — even
an untouched record-with-managed-field local segfaults — so it was reverted
rather than shipped half-done).

## Scope (land together, each oracle-tested vs x86-64)

1. **Prologue zero-init.** `parser.inc` errors when `zeroBytes > TARGET_PTR_SIZE`
   on non-x86-64. x86-64 does `lea + rep stosb`. Cover it per target with a
   portable `PXXMemZero(addr, n)` call or an inline byte loop. First use must see
   nil fields so an ARC-correct whole-record copy releases nil, not stale stack.
   *Necessary but not sufficient on its own.*
2. **Body ARC ops.** A managed *record* local's field assignment (`r.name := s`)
   needs retain-new / release-old of the managed field; a *variant* local needs
   assignment / clear / write. Even an **untouched** record-with-managed-field
   local segfaults on arm32 today, so a path beyond the body is also wrong —
   diagnose before building (suspect the field-store / variant-store lowering or
   a record-layout/RTTI interaction in the prologue).
3. **Epilogue release.** The cross epilogues only release scalar `tyAnsiString`
   locals (`symtab.inc`); record managed-fields, variants, and arrays-of-managed
   are skipped (leak). The x86-64 `EmitManagedLocalCleanup` walk is
   `TARGET_X86_64`-gated. Add a per-target managed-local release that walks
   records/variants/arrays, mirroring the x86-64 cleanup. Interacts with
   feature-cross-exceptions (release also runs during unwinding).

## Acceptance

Oracle tests (vs x86-64) for: a record-with-managed-field local (assign managed
field + int field, print); a variant local (int then string, print); an array of
AnsiString local. No leaks (managed locals released at scope exit). arm32 first,
then i386 / AArch64. arm32 `compiler.pas` cross-compile advances past line 13288.
Self-host + threadsafe fixedpoints stay byte-identical.

## Log
- 2026-06-13 — opened from the codegen-gaps item-1 diagnosis. Zero-init prototype
  reverted (compiles, crashes at runtime); full sub-arc captured here.
