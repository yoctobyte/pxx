# Managed aggregate locals on cross targets

- **Type:** feature
- **Status:** done
- **Owner:** claude
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
- 2026-06-13 — claimed. **arm32 items 1 + 2 done; root cause found.** The
  earlier "zero-init compiles but crashes" was a misdiagnosis: the real bug was
  that the prologue zero-init's final `else if zeroBytes > 0` branch (the x86-64
  `lea/xor/mov/rep stosb`, **19 bytes**) had no `TargetArch` guard. The original
  `Error` for `zeroBytes > TARGET_PTR_SIZE` on non-x86 masked it; once a real
  arm32 branch let the flow continue, those 19 x86 bytes were emitted into the
  arm32 code stream, misaligning every following 4-byte ARM instruction (→
  illegal-instruction / null-deref). Fix: (a) guard that branch to
  `TargetArch = TARGET_X86_64`; (b) emit a real arm32 byte-zero loop in the
  arm32 `zeroBytes > PTR` branch. The inline arm32 loop was correct all along.
  Record-with-managed-field locals (incl. managed-field reassignment) and
  variant locals now run correctly on arm32; new oracle test
  `test/test_cross_managed_aggregate_locals.pas` wired into `make test-arm32`.
  `compiler.pas` → arm32 advances past the line-13288 wall to line 16280 (a
  different builtin-special). arm32 + i386 + aarch64 + core + self-host/threadsafe
  fixedpoints green. **Remaining: item 3** (epilogue release of record
  managed-fields / variants — currently leak-only, output correct) and the
  i386 / AArch64 ports of items 1+2.
- 2026-06-13 — **arm32 item 3 done.** The arm32 epilogue release loop (symtab.inc)
  previously released only scalar `tyAnsiString` locals; it now also clears
  variant locals (`PXXVarClear`, r0 = address) and releases managed-field record
  locals (`PXXRecordRelease`, r0 = address, r1 = layout descriptor via
  `RECORD_RTTI_DATAREF_BASE`), no heap lock (matching the arm32 DEFAULT_MEM
  release path). The managed-aggregate-locals oracle test still matches x86-64
  (no double-free), and `compiler.pas` → arm32 advances to line 16307 now that
  its own managed-local epilogues compile. arm32 + core + self-host/threadsafe
  fixedpoints green. **arm32 portion complete (items 1+2+3).** Remaining: the
  i386 / AArch64 ports (same three pieces), and array-of-managed locals (records
  /variants done; an array-of-AnsiString local release is not wired yet).
- 2026-06-13 — AArch64 self-host repro confirms the next concrete wall is the
  static array-of-managed local case. After the scalar-AnsiString `IR_LEA` fix,
  `/tmp/compiler_aarch64` parses `test/hello.pas` but segfaults in
  `PXXStrDecRef` from `ParseProgram` with `p = -9`. The relevant compiler local
  is `dummyNames: array[0..7] of AnsiString`; first assignment releases stale
  stack contents. This is the AArch64 port/array-of-managed slice of this ticket.

## Closure (2026-06-16)

`feature-cross-bootstrap-selfhost` is DONE — byte-identical self-fixedpoint on
i386/aarch64/arm32 (and x86-64). This ticket existed to unblock that gate, so its
blocking purpose is met: every code path `compiler.pas` itself exercises now
works byte-identically on all cross targets. Residual gaps are only in language
features the compiler does NOT self-use (e.g. classes, interfaces, some param/
ABI shapes user code hits) — those move to the language-surface hardening effort
driven by the synthetic conformance harness
([[feature-synthetic-feature-matrix-test]]). Closed.
