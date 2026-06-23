# bug: `PChar('')` / `PChar(emptyAnsiString)` yields nil, not an empty C string

- **Type:** bug (Track A — IR lowering / string model) — FPC-compat, nil-deref risk
- **Status:** backlog
- **Found:** 2026-06-23, generalized from the recurring PChar(empty) guard hack in
  the lib (Track B)
- **Severity:** medium-high — every `PChar(s)` passed to a C/PAL call where `s`
  can be empty is a latent nil dereference (segfault), so callers hand-guard it.

## Gap

A managed empty string is a **nil** handle, so `PChar` of it is a nil pointer.
FPC guarantees `PChar('')` is a valid pointer to a static `#0` byte (an empty C
string), never nil.

```pascal
var a: AnsiString; p: Pointer;
begin
  a := '';
  p := PChar(a);
  { fpc: p is non-nil (-> a #0 byte)    pxx: p = nil }
end.
```

Verified (managed strings): `a := ''; PChar(a) = nil` is True; `PChar('hi')` is
non-nil. So any C/PAL call `f(PChar(a))` that does not nil-check (`strlen`,
`open`, `write`, …) dereferences nil when `a` is empty.

## Why it matters / the hack

Library code must hand-guard every PChar-of-maybe-empty site, e.g. branch on
`s = ''` before the call, or ensure the string is never empty. Risk sites already
in the tree: `lib/rtl/textfile.pas` (`PalOpen(PChar(f.Name))`, `PalWrite(...,
PChar(s), Length(s))`), `lib/rtl/sysutils.pas` (`PalOpen(PChar(path))`,
`PalStatAt(fd, PChar(name))`), `lib/rtl/dns.pas`. The expectation is that the
**language** makes `a := ''; PChar(a)` valid — no caller guard.

## Root cause

`PChar(tyAnsiString)` IR lowering (compiler/ir.inc, AN cast adapter ~1977/1982 +
the TypesCompatible string→Pointer auto-marshal) passes the managed handle as-is
(it is already a char pointer when non-empty). For an empty managed string the
handle is nil — pxx models the empty managed string as nil, not as a non-nil
empty buffer (a deliberate string-model choice; see the managed-string arc).

## Expected / fix sketch

`PChar`/`PAnsiChar` of a managed string must never yield nil:
- In the PChar adapter for a tyAnsiString operand, emit a nil-check that
  substitutes the address of a shared static `#0` byte when the handle is nil
  (`handle <> nil ? handle : @PXXEmptyStr`), mirroring FPC's behavior.
- A single shared read-only `#0` byte in rodata suffices for all such sites.
- Frozen `tyString` already points at an inline `[len][chars#0]` buffer (+8 skip),
  so the empty frozen case is fine; this is specifically the managed-nil case.

Note: this is the PChar/const-char* path; it does NOT change the managed-string
model itself (empty stays nil internally), only the C-boundary adapter.

## Gate

`make test` + an external-C test passing `PChar('')` to a libc function
(`strlen` → 0, not a segfault); FPC oracle-match.
