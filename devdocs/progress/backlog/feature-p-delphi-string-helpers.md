---
track: P
prio: 70
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

## Triage 2026-08-19 (Track D re-triage pass, pin v363)

**Genuine feature, still wanted, unchanged.** `s.Length` / `s.ToUpper` on an
`AnsiString` still stops at the diagnostic this ticket was filed alongside:

```
error: a string has no members here: pxx does not implement Delphi's string
helpers (s.Length, s.ToUpper, s.Trim, s.Substring) — use the intrinsics
Length(s), UpperCase(s), Trim(s), Copy(s, i, n)
```

Compat surface (Delphi/FPC accept it) with a loud, actionable refusal, so it
stays a feature rather than being promoted.

**Landmine for whoever takes it — there IS a negative test on this refusal.**
`Makefile:4170-4171` runs `test/test_scalar_member_fail.pas` under `!` and
greps for `a string has no members here`. Implementing the helpers makes that
program compile and reds `test-core`, which `gate.sh quick` does not run, so
the break would surface only through Track T. Re-point the test at whatever
stays refused (a member that `TStringHelper` does not declare) **in the same
commit**, the way `test_asm_att_reject.pas` had to be re-pointed on
2026-08-19. The neighbouring `test_scalar_member_int_fail.pas` — `a value of
this type has no members` — is unaffected, since integer helpers are out of
scope here.

> **SUPERSEDED 2026-08-29 (coordinator), and this one was an INSTRUCTION rather
> than a claim — following it would have DONE DAMAGE.** The landmine above does
> not exist. `test/test_scalar_member_fail.pas` has **no `uses` clause** (verified:
> `program test_scalar_member_fail;` at `:19`, `writeln(s.Length)` at `:23`, 24
> lines, no `uses`). FPC refuses that exact program too — `s.Length` without
> `uses sysutils` is `Illegal qualifier` even under the modeswitch. A
> **sysutils-scoped** `TStringHelper` therefore leaves it **correctly refused,
> for the same reason FPC refuses it.**
>
> Re-pointing it would have retired a test that is right as written — and which
> is now *more* precisely right than when it was written, because it pins that
> the helpers are **unit-scoped rather than ambient.** Found by frankB, which
> read the test before obeying the instruction about it. The line reference had
> drifted as well: `Makefile:5419`, not `:4170-4171`.
>
> **Left in place rather than deleted**, per the record-keeping rule — it is an
> accurate account of what a past session believed. But note the asymmetry it
> exposes: **a stale CLAIM invites checking; a stale INSTRUCTION invites
> compliance.** Everything in this repo's stale-prose family so far has been a
> claim — a `blocked-by` outliving its blocker, a stall note, a withdrawn limit.
> This is the first *directive*, and directives are the expensive half: it named
> a file, a line, a reason, and a precedent, and the more specific it got the
> more it read as verified.


## Measured state, 2026-08-25 (probing before starting)

Rather more of this already works than the ticket assumed, and one part of the
scope was missing.

**Works today, matching fpc 3.2.2 byte for byte:** a `type helper for string`
declared in a UNIT and used from a program, on `string` and on `AnsiString`,
with a plain VARIABLE receiver — `s.Twice`, `s.IsEmpty`, `(s + 'x').Twice`.
So "whatever binds a helper to the built-in string kinds rather than to a named
type" is not missing; it is done. What is left of the ticket is largely the
**sysutils-side declaration** of `TStringHelper` with FPC's signatures — which
is `lib/rtl` and therefore Track **B** file-ownership, not P. Worth re-tracking
before someone claims this as a P item and finds themselves editing lib/.

**Refused, and correctly so:** `sh.Twice` on a ShortString — FPC says
`Illegal qualifier` too, so a `helper for string` does not apply to a
ShortString in either compiler.

**The real P-side gap, and an addition to Scope above: the RECEIVER must be
generalised past a declared variable.** FPC accepts, and pxx does not:

| spelling | fpc | pxx |
| --- | --- | --- |
| `'xy'.Twice` (literal receiver) | `xyxy` | parse error at the `.` |
| `F.Twice` (call result) | `qq` | parse error at the `.` |
| `Copy(s,1,1).Twice` | `aa` | parse error at the `.` |
| `s.Twice.Twice` (chained) | `aaaa` | refused |
| `(F).Twice` | `qq` | refused |

The last two printed **wrong numbers** until 2026-08-25 — see
[[bug-p-a-member-on-a-computed-value-silently-reads-the-values-own-bytes]],
which made them loud. The dispatch is keyed on the receiver SYMBOL
(`pasparser_lval.inc`, the TYPE-HELPER dispatch block, `if (idx >= 0) and ...`),
and a helper method's Self is by-reference, so a computed receiver needs
materialising into a temp first — the move `GenMakeStringValueIndex` already
makes for `(s + 'x')[3]`.
