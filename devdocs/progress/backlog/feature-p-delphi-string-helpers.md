---
track: P
prio: 45
type: feature
---

# feature(P): Delphi's TStringHelper surface — `s.Length`, `s.ToUpper`, `s.Trim`, `s.Substring`

**Filed 2026-08-16 as the constructive half of
`bug-p-a-member-on-a-scalar-silently-reads-the-values-own-bytes`.** That bug is
fixed: `s.Length` used to compile and print the four bytes of `'Hell'` as an
Int32, and now it is a clear error naming this gap. The error is the honest
answer, not the finished one — this ticket is the finished one.

## Why it is worth doing

Method-style string access is how modern Delphi and current FPC code is written.
FPC compiles it under `{$modeswitch typehelpers}` against sysutils'
`TStringHelper`, and a program written that way is not exotic — it is the
default style in anything written against Delphi 2009+ conventions. Every such
program currently stops at the first `s.Length`. That makes this a **compat**
item under the frontend's own reference (FPC/Delphi), not a dialect extension.

Note the pxx-side asymmetry that makes the refusal only a stopgap: type helpers
themselves already work here — `type helper for Integer` with a `Sq` method
parses, compiles and answers 49 for `7.Sq` (verified 2026-08-16). So the
machinery is present; what is missing is the sysutils-side declaration of the
helper for the string types, plus whatever binds a helper to the built-in string
kinds rather than to a named type.

## Scope

The commonly-used members, against FPC's `TStringHelper` signatures (which are
Delphi's, so 0-based indexing for `Substring`/`IndexOf` — **not** Pascal's
1-based `Copy`; getting that wrong would be a silent wrong answer of exactly the
kind this ticket exists to retire):

`Length`, `ToUpper`, `ToLower`, `Trim`/`TrimLeft`/`TrimRight`, `Substring`,
`IndexOf`/`LastIndexOf`, `StartsWith`/`EndsWith`/`Contains`, `Replace`,
`Split`, `IsEmpty`, `PadLeft`/`PadRight`.

## Gate

`make compiler/pascal26` + a new positive test whose `.expected` is FPC's own
output (built with `{$modeswitch typehelpers}`), so the 0-based/1-based boundary
is pinned by the oracle rather than by hand + `tools/gate.sh quick`. The two
negative tests from the bug (`test_scalar_member_fail.pas`,
`test_scalar_member_int_fail.pas`) must be **retired with this feature** for the
string arm — implementing the helpers makes `s.Length` compile and turns its own
refusal test red, which the quick tier can see (it is in `make test`'s negative
block). The int arm stays: `i.Bogus` must still be refused.
