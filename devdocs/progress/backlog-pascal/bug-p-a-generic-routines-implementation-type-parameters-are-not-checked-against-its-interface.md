---
track: P
prio: 30
type: bug
blocked-by: []
status: backlog
owner: ""
created: 2026-09-05
summary: "A unit may declare `generic procedure Test<T>;` in its interface and implement `generic procedure Test<S>;` — different type-parameter names — and pxx accepts it silently. FPC rejects it. Conformance rows tgenfunc17.pp and tgenfunc18.pp are the two live FAILs in an otherwise 347/2 run. NOT a regression to revert: the pin REFUSED these files because it did not support `generic procedure` at all, so its %FAIL pass was accidental; 71deb21d4 added the syntax and exposed a check that never existed."
---

# A generic routine's implementation type parameters are not checked

Measured 2026-09-05 at `abe92579b`, running `tools/run_pascal_conformance.sh`
as wired (`--strict-case --strict-operator`, driver-synthesis branch — these are
unit-shaped tests).

```pascal
unit tgenfunc17;
{$mode objfpc}{$H+}
interface
generic procedure Test<T>;      { declared with T }
implementation
generic procedure Test<S>;      { implemented with S — FPC rejects }
begin
end;
end.
```

| | tgenfunc17 / tgenfunc18 |
| --- | --- |
| fpc 3.2.2 | rejected (the suite marks both `{ %FAIL }`) |
| pxx at `abe92579b` | **ACCEPTED, exit 0, binary produced** |
| pxx at pin v403 | rejected — see below |

## The pin's rejection is NOT the check, and this is the part worth reading

The pinned compiler says:

```
error: unexpected token in a unit interface section: it starts no declaration
  near: unit tgenfunc17 ; interface >>> generic procedure Test
```

It never looked at the type parameters. **It refused the whole syntax**, and a
`%FAIL` row scores any refusal as a pass — so the row was green for a reason
that has nothing to do with what the test is about. `71deb21d4` (2026-09-04,
*"a `generic function` can be declared in a unit"*) added the syntax, and the
row went red the moment the compiler became able to read the file.

**So this is not a regression and reverting anything would be wrong.** It is a
capability gain that revealed a missing check, and the archive carries the
accidental pass: `devdocs/progress/tstate/conformance.tsv` records `pass` for
both rows as of 2026-09-02, measured by a compiler that could not parse them.

## Is it even a defect? Yes, and the rule says so specifically

CLAUDE.md: *"Us accepting what FPC rejects is not a defect"* — but also, for
inputs only a mistake produces, *"prefer the answer that leaves the mistake
visible."* An interface saying `<T>` and an implementation saying `<S>` is a
programmer error every time; accepting it silently is the answer that HIDES it.
So the wanted behaviour is a diagnostic, not FPC parity, and this is ranked as
a missing diagnostic rather than as a compat gap.

## Gate

`tools/run_pascal_conformance.sh` reaching **349 pass / 0 fail** (from 347/2),
with the count asserted rather than the exit code: **the harness SKIPs and exits
0 when `library_candidates/fpc-testsuite` is absent**, so a green there proves
nothing unless the suite is installed
(`tools/install_lib_candidates.sh fpc-testsuite`). Plus a positive control that
the matching case still compiles — `<T>` in both halves must not start failing.
