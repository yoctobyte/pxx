---
slug: bug-p-a-resourcestring-is-not-addressable
track: P
prio: 55
type: bug
status: backlog
blocked-by: []
summary: "`@SomeResourceString` is `error: undefined variable` — pxx parses a `resourcestring` section as a plain const section (pasparser_proc.inc:4783), and a const has no address. FPC makes resourcestrings addressable (they are runtime-replaceable variables), which is what `Exception.CreateRes(@SArgumentOutOfRange)` — the Delphi/FPC idiom, 3 sites in generics.defaults.pas — depends on."
---

# A `resourcestring` is not addressable

- **Track P** (Pascal frontend — `resourcestring` handling).
- Found 2026-08-28 by frankB while implementing
  [[feature-sysutils-delphi-exception-api-gaps-found-by-rtl-generics]].
  Measured against pin **v389** (`325b4479070a`).

## Repro

```pascal
program rs;
resourcestring
  SFoo = 'out of range';
var p: ^string;
begin
  p := @SFoo;          { pxx: error: undefined variable (SFoo)   fpc: fine }
  WriteLn(p^);
end.
```

## The boundary, measured — only resourcestring differs

| declaration | pxx `@` | fpc `@` |
| --- | --- | --- |
| `resourcestring SFoo = 'x'` | **error** | works |
| `const SFoo = 'x'` (untyped) | error | error |
| `const SFoo: string = 'x'` (typed) | works | works |
| `var SFoo: string = 'x'` | works | works |

Three of the four rows already agree, including the untyped-const row where
BOTH refuse — so this is not general laxness about addressing constants, and
the fix is not "let `@` take a const". It is one row.

## Cause

`compiler/pasparser_proc.inc:4783` routes a `resourcestring` section straight
into `ParseConstSection`, with the comment "`resourcestring` sections (FPC
rtlconsts et al) register as plain [consts]". That was the right call for
*reading* one — `WriteLn(SFoo)` works — and it is what makes vendored units
carrying `resourcestring` blocks compile at all. It only falls short where the
address is taken.

In FPC a resourcestring is not a constant: it is a runtime-replaceable variable,
which is the whole point of the construct (a translation layer rewrites it at
startup). That is why `@` works there and why the Delphi RTL idiom is built on
it.

## Why it matters

`Exception.CreateRes(ResString: PString)` is the Delphi/FPC resource-string
constructor, and every call site spells its argument `@SSomeResourceString`:

```pascal
raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);
```

Three such sites in `generics.defaults.pas` (many more in
`generics.collections`). `CreateRes` itself is Track B's and is implemented —
it takes a `PString`, dereferences it, and constructs. **The library side is
done; the call sites cannot be written until this lands.** No workaround was
added: the platonic spelling is the FPC one, and reshaping the consumer is not
available anyway since it is vendored.

## Fix sketch

Give a `resourcestring` section's entries storage — a typed string variable
initialised to the literal — rather than folding them as constants. Reading is
unchanged; `@` then works for free, and a future translation hook has somewhere
to write. The `ParseConstSection(-1, 0)` call is where the two paths currently
merge.

## Gate

The repro above prints `out of range`; the other three rows of the table are
unchanged (in particular an untyped `const` must STILL refuse `@`); `make test`
+ self-host fixedpoint.

## Corpus evidence, measured 2026-08-28 (frankA)

Verified against the rtl-generics tree in `library_candidates/`, which is **not
present on every checkout** — a search for these symbols from a tree without the
corpus is structurally blind and returns exactly what a refutation returns.
Recorded here so the next holder does not have to re-establish it.

The addressed symbol is the corpus's **own `resourcestring`**, not anything in
our RTL:

- `generics.strings.pas:25` — `resourcestring`
- `generics.strings.pas:26` — `SArgumentOutOfRange = 'Argument out of range';`

**`lib/rtl/rtlconsts.pas:13` is a red herring, and worth naming as one** because
it is the first thing a grep finds. It declares an `SArgumentOutOfRange` too, as
a plain `const`, deliberately (that unit has no resource tables). But
`generics.defaults.pas` — the unit where the failures were measured — has
`uses Classes, SysUtils, Generics.Hashes, TypInfo, Variants, Math,
Generics.Strings, Generics.Helpers` and **does not use `RtlConsts` at all**, so
our constant is not in scope there and cannot be the symbol involved. Fixing
anything in `lib/rtl` would change nothing.

This matters for the *reasoning*, not the conclusion: "a plain const has no
address" points at the RTL and invites a needless Track B change. The real shape
is the one this ticket already names — a genuine `resourcestring` section, which
we parse as a plain const section (`pasparser_proc.inc:4783`), and which FPC
makes addressable because resourcestrings are runtime-replaceable variables.

### Site counts, corrected

Earlier notes give "3 sites in `generics.defaults.pas`" and a corpus figure of
"5". Both are low; the 5 was an *error* count from one aborted compile, not a
site count. Measured:

| what | count |
| --- | --- |
| `CreateRes(@SArgumentOutOfRange)` in `generics.collections.pas` | 18 |
| `CreateRes(@SArgumentOutOfRange)` in `generics.defaults.pas` | 7 |
| other `CreateRes(@…)` — `SDuplicatesNotAllowed`, `SDictionaryKeyDoesNotExist`, `SArgumentNilNode` | 1 each |
| **total `CreateRes(@…)` sites in the corpus** | **28** |

So this blocks `generics.collections.pas` harder than `generics.defaults.pas`,
which is the larger unit of rung 6 and has not been probed past its earlier
walls yet. Do not size this from the defaults-only figure.
