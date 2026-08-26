---
slug: feature-p-fpc-assigned-enum-ordinals-with-colon-equals
track: P
prio: 72
type: feature
blocked-by: []
summary: "An enum with explicit ordinals written FPC-style — `(ms_on := 1, ms_off := 2)` — is refused. objfpc mode spells assigned enum values with `:=` where Delphi mode uses `=`; pxx accepts only the Delphi spelling. Second wall behind the FPC-compiler define profile: globtype.pas:800, which cclasses pulls in."
status: done
---

# FPC `{$mode objfpc}` assigned-enum ordinals use `:=`, not `=`

Found 2026-08-21 immediately behind
[[feature-mimic-fpc-compiler-define-profile]]. This is the wall on the
`cclasses` / `globtype` path — the sibling of
[[feature-p-fpc-global-operator-overload-declarations]], which is the wall on
the `cutils` path.

## Repro

```pascal
{ FPC 3.2.2 compiler/globtype.pas, line 800 }
tmsgstate = (
  ms_on := 1,
  ms_off := 2,
  ms_error := 3,
  ...
);
```

```
$ pascal26 --mimic-fpc-compiler p_cclasses.pas
Expected: ), but got:  (Kind: 63, Line: 1103)
pascal26:1103: error: unexpected token
  near:  type tmsgstate   ms_on >>>
```

(Line 1103 does not exist in globtype.pas, which is 843 lines — see
[[bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file]].)

## What it is

Assigning explicit ordinals to enum members. **The spelling differs by mode**,
which is the whole of this ticket:

| mode | spelling |
| --- | --- |
| Delphi / `{$mode delphi}` | `(ms_on = 1, ms_off = 2)` |
| **objfpc / `{$mode objfpc}`** | `(ms_on := 1, ms_off := 2)` |

pxx accepts the `=` form (the error is "Expected: )", i.e. it parsed the
identifier and then wanted the list to end). So this is one token in one place,
not a feature — the enum machinery behind it already exists.

Worth checking while there whether the two spellings should BOTH be accepted
unconditionally or whether the `:=` form belongs behind `-Mobjfpc`. pxx's
dialect is deliberately lax by default and FPC-parity strictness lives behind
per-feature flags, which argues for accepting both always — but that is the
call to state in the ticket rather than assume. See
`devdocs/dev/normalise-dont-special-case.md`: two spellings of one concept want
one path, not a second one.

## Gate

`globtype.pas` parses; `cclasses.pas` gets past it under
`--mimic-fpc-compiler`. Pascal suite green + self-host byte-identical.

## Outcome — 2026-08-26

One token, one place, as the ticket predicted. `ParseEnumMembers`
(`compiler/pasparser_decl.inc:50`) tested `CurTok.Kind = tkEq`; it now tests
`tkEq or tkAssign` and everything downstream — `AddEnumVal`, the
continue-from-value+1 rule, `EnumTypeHasHoles`, the unscoped-member `SymEnumId`
tagging — is unchanged and shared.

### The open question in the ticket, answered

*"Whether the two spellings should BOTH be accepted unconditionally or whether
the `:=` form belongs behind `-Mobjfpc`."*

**Both, unconditionally.** Two reasons, and they agree:

- `normalise-dont-special-case.md` — gating one spelling on a mode makes a
  second path for one concept, which is the thing that document exists to
  refuse. The enum machinery behind it is already one path; the token should be
  too.
- The FPC-parity ceiling in `CLAUDE.md` — *we accept a form FPC rejects = not a
  defect*. Accepting `:=` in what FPC would call delphi mode costs nothing and
  breaks nothing; refusing it costs a mode-tracking mechanism.

Measured while there: **FPC itself accepts the two spellings INTERLEAVED in one
list** (`(m_a := 2, m_b = 4, m_c)` compiles under `-Mobjfpc`), so a mode-gated
implementation would have had to allow the mix anyway. That is in the test.

### Gate — the ticket's own, met

```
$ pascal26 --mimic-fpc-compiler -Fu<fpc-source>/compiler p_globtype.pas p_globtype
ok: p_globtype  [code=118047B data=19040B bss=46440B procs=234]
```

`globtype.pas` does not merely parse, it compiles clean. `cclasses.pas` now gets
past it and stops at the NEXT wall, which is the already-filed sibling:

```
pascal26:298: error: binary operator must take exactly two parameters
  in: <fpc-source>/compiler/constexp.pas
```

— i.e. [[feature-p-fpc-global-operator-overload-declarations]], unchanged and
still open. (FPC compiler sources are not in `library_candidates`; they live at
`/data/borg-rescue/home-rene/src/fpc-source/compiler` on this box, which is
where both runs above point.)

### Measured

`test/test_enum_assigned_ordinal_colon_equals.pas` (+ `.expected`, wired into
`test-core`), byte-identical to `fpc -O- -Mobjfpc` 3.2.2 on every row —
`globtype`'s own tmsgstate shape, the Delphi `=` form, the mixed list, hex
values, and the identity checks that prove `:=` goes through the same
`AddEnumVal` path (`m = ms_warn` TRUE, `m = ms_on` FALSE):

```
1 2 3 4 10
5 7 8
2 4 5
17 34 51
4 8 5 34
TRUE FALSE
TRUE TRUE
```

### Gate

`make compiler/pascal26` byte-identical (9bb20fbd0c0f) · `tools/gate.sh quick`
GREEN · pascal-conformance 346/0/170/34 · c-conformance 220/0.

## Log
- 2026-08-26 — resolved, commit 47effda1c.
