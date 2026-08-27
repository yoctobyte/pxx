---
prio: 55
track: B
owner: unassigned
---

# SysUtils gaps found by rtl-generics: `EArgumentOutOfRangeException`, `CreateRes`, `System.Error`

- **Type:** feature (RTL surface) — **Track B** (libraries).
- **Found by:** the rung-6 `rtl-generics` diagnostic, Track P — see
  [[feature-pascal-corpus-expansion]] for the full partition and method.
- **Binary:** `2c4e727d4b63`, verified self-host fixedpoint at `4f380892c`.
- **Companion:** [[feature-typinfo-facade-unit]] — the other Track B wall on the
  same corpus. These are independent; neither blocks the other.

Three small, unrelated-to-typinfo gaps that `generics.defaults.pas` hits. Each
is a named, bounded addition — together they are the entire non-typinfo Track B
surface that corpus needs.

## 1. `EArgumentOutOfRangeException` — 3 sites in `defaults`, many in `collections`

`lib/rtl/sysutils.pas:157` has `EArgumentException = class(Exception) end;` but
not the out-of-range descendant. Delphi/FPC declare it as a descendant of
`EArgumentException`. One line.

## 2. `Exception.CreateRes(@ResourceString)` — 3 sites

The resource-string constructor, called as
`EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange)`. It takes a
pointer to a resource string rather than a string. Whether pxx wants a real
resource-string mechanism or can treat `CreateRes(P: PResStringRec)` as
"dereference and Create" is a design call worth making deliberately — if it is
the latter, say so in a comment, because the name promises more than it does.

## 3. `System.Error(reRangeError)` — 7 sites

The RTL `Error` procedure plus the `TRuntimeError` enumeration. In
`rtl-generics` every use is the `else` arm of a `case` over a type kind, i.e.
"this cannot happen" — so a faithful `Error` that raises the corresponding
runtime error is enough; none of the 7 sites depends on a specific exit code.

Note this one is squarely inside CLAUDE.md's "error handling stays ours by
default" ruling — the requirement here is only that `Error` *exists and halts*,
not that its runtime-error numbers match FPC's.
