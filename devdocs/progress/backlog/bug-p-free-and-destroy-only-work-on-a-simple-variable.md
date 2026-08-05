---
summary: "`.Free` is only accepted on a plain variable — `a[0].Free`, `r.f.Free`, `h.f.Free` are all `\"Free\": no such member on this record/class`, and `v.Destroy` fails even on a plain variable"
type: bug
track: P
prio: 60
---

# `.Free` / `.Destroy` off anything but a simple variable

- **Type:** bug — Track P (Pascal frontend; the code is in the shared
  `compiler/parser.inc`)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** `tools/fpc_diff_probe.sh` thread cases — three of them freed an
  array of workers with `t[k].Free` and every one failed to compile.

## Repro

```pascal
program af;
uses SysUtils;
type
  TFoo = class n: Integer; end;
  TBox = record f: TFoo; end;
  THolder = class f: TFoo; end;
var r: TBox; h: THolder; a: array[0..1] of TFoo; d: array of TFoo; v: TFoo;
begin
  ...
end.
```

| expression | pxx |
| --- | --- |
| `v.Free` | **ok** |
| `v.Destroy` | `error: "Destroy": no such member on this record/class` |
| `r.f.Free` (record field) | `error: "Free": no such member ...` |
| `h.f.Free` (class field) | `error: "Free": no such member ...` |
| `a[0].Free` (static array) | `error: "Free": no such member ...` |
| `d[0].Free` (dynamic array) | `error: "Free": no such member ...` |
| `FreeAndNil(r.f)` | **ok** — the workaround |
| `a[0].ClassName` | **ok** — other TObject members are fine on any designator |

FPC compiles all of them.

## Why this shape matters

`FList[i].Free`, `Workers[k].Free`, `FOwner.Child.Free` are everyday Pascal.
The failure is at least loud — a compile error, never a wrong value or a
missed destructor — but it forces `FreeAndNil` or a temporary at every site,
which is exactly the kind of reshaping `CLAUDE.md`'s platonic-code rule says
not to do quietly.

That `a[0].ClassName` works while `a[0].Free` does not is the tell: this is not
about member lookup on an indexed base in general.

## Where to look

`Free` is not a member of a `TObject` the frontend knows; it is recognised by
ad-hoc token-shape special cases in `compiler/parser.inc` — e.g. `:3911`
(`CaseEqual(fieldName, 'Free')` gated on the *next* token), `:20462`, `:20487`,
and `:20669` (`CaseEqual(GetTokenStr(TokPos+1), 'Free')`, i.e. an identifier
followed literally by `.Free`). A base that is an index or a field access does
not match any of those shapes, so it falls through to ordinary member lookup
and there is no `Free` to find. `Destroy` has no such special case at all,
which is why even `v.Destroy` fails.

**This is where to look, not a diagnosis** — the fix could as easily be "give
the root class a real `Free`/`Destroy` so the special cases can go" as "extend
the special cases". Measure before committing to either; see
`devdocs/dev/debugging-playbook.md`.

## Gate

Track P: `make test` + self-host fixedpoint (byte-identical). Track P catch —
the Pascal frontend lives in the shared `lexer.inc`/`parser.inc`, so this must
not be edited concurrently with Track A. If the fix is "give TObject real
members", that is an A-shaped change to `symtab.inc`/`defs.inc` and should be
filed as such.
