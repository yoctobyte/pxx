---
prio: 55
track: B
owner: frankB
status: done
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

> **[annotation 2026-08-28, frankA — the measurement below is left as recorded;
> only this pointer is added]** The site count is **7**, not 3, in
> `generics.defaults.pas`. See `bug-p-a-resourcestring-is-not-addressable`.

`lib/rtl/sysutils.pas:157` has `EArgumentException = class(Exception) end;` but
not the out-of-range descendant. Delphi/FPC declare it as a descendant of
`EArgumentException`. One line.

## 2. `Exception.CreateRes(@ResourceString)` — 3 sites

> **[annotation 2026-08-28, frankA — same]** Also **7**, and it is *the same
> seven lines* as §1 (2960, 3049, 3075, 3078, 3182, 3218, 3221): each spells
> both symbols, so these two sections are **one measurement filed twice**, not
> two counts agreeing. Corpus-wide: **28** `CreateRes(@…)` sites, 18 of them in
> `generics.collections.pas`. See `bug-p-a-resourcestring-is-not-addressable`.

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

## Resolution (2026-08-28, frankB)

All three landed in `lib/rtl/sysutils.pas`, verified against `$(PXX_STABLE)`
v389 (`325b4479070a`). Regression: `test/lib_sysutils_delphi_exceptions.pas`
(21 rows) in `make lib-test`.

### 1. `EArgumentOutOfRangeException`

A descendant of `EArgumentException`, as Delphi and FPC declare it — confirmed
by running FPC 3.2.2 rather than assumed, because a sibling would make
`on E: EArgumentException` silently not fire. The test asserts the ancestry in
both directions (it IS caught as the parent; the parent is NOT an instance of
it).

### 2. `CreateRes` / `CreateResFmt`

Implemented as **dereference and construct**, which is the ticket's second
option, and the comment at the declaration says so — the name promises a
resource-string mechanism that is not there. That is defensible rather than a
stub: pxx parses `resourcestring` sections as plain consts
(`pasparser_proc.inc:4783`), so a resourcestring here IS its literal, the
observable behaviour matches FPC's for any program that never re-translates, and
a real mechanism can be slid underneath without changing the signature.

The parameter is spelled `PResStringRec` (Delphi's name), **not** FPC's
`PString`, deliberately: `lib/rtl/typinfo.pas` already exports a `PString` that
is `^string[255]` — a frozen pointer for reading RTTI name blobs — and a program
doing `uses typinfo, sysutils` would get whichever came last. Two incompatible
meanings for one name in one RTL produces a wrong answer rather than an error.

**The call sites remain blocked, and not by this code.** `@SSomeResourceString`
— how every real call is written — is `error: undefined variable`, because a
const has no address. Filed as
[[bug-p-a-resourcestring-is-not-addressable]] (Track P), with the measured
boundary: of the four ways to declare a string, only `resourcestring` differs
between pxx and FPC; untyped `const` refuses `@` in BOTH, so the fix is not
"let `@` take a const". No workaround was added — the platonic spelling is
FPC's, and the consumer is vendored anyway.

### 3. `TRuntimeError` + `Error`

The enumeration is FPC 3.2.2's, **read off a running FPC program**, and this
mattered: its tail is not Delphi's. FPC ends `reQuit` / `reCodesetConversion` /
`reNoDynLibsSupport` / `reThreadError` where Delphi has the monitor errors — 29
members, `reRangeError` = 4. Recalling that list gets it wrong; the ordinals are
asserted because a vendored `case` compares against them.

`Error` **raises** a catchable exception mapped to the nearest SysUtils class.
FPC **halts** with an uncatchable runtime error 201. That divergence is
deliberate on the grounds the ticket names plus one more: it matches OUR runtime,
where a division by zero is already a catchable `EDivByZero` and a bad
`StrToInt` an `EConvertError` (measured), so a halting `Error` would be the odd
one out in its own RTL. Recorded in `devdocs/dev/pascal-dialect-divergences.md`
**together with its cost** — a catchable `Error` can be swallowed by a
surrounding handler, turning a "cannot happen" arm into a handled path, and all
7 call sites are exactly such arms. If it bites, the fix is to halt.

No error numbers are asserted anywhere, per the ruling.

### What was verified against FPC, precisely

The test's first **18 rows run byte-identically under FPC 3.2.2**; it then
diverges at `Error()` by design, where the FPC run terminates. The header states
that boundary rather than claiming the file is portable.

### Gate

`make lib-test` green, `make demos` 35/35, both against v389.

## Log
- 2026-08-28 — resolved, commit a6b06ebc1.
