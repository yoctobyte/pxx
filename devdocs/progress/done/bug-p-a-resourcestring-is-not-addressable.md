---
slug: bug-p-a-resourcestring-is-not-addressable
track: P
prio: 65
type: bug
status: done
blocked-by: []
summary: "`@SomeResourceString` is `error: undefined variable` — pxx parses a `resourcestring` section as a plain const section (pasparser_proc.inc:4783), and a const has no address. FPC makes resourcestrings addressable (they are runtime-replaceable variables), which is what `Exception.CreateRes(@SArgumentOutOfRange)` — the Delphi/FPC idiom — depends on. Measured 2026-08-28: **28 `CreateRes(@…)` sites** in the rtl-generics corpus, 18 of them in `generics.collections.pas` and 7 in `generics.defaults.pas`; the addressed symbol is the corpus's own resourcestring (`generics.strings.pas:26`), NOT our `lib/rtl/rtlconsts.pas` const, which `generics.defaults.pas` does not even use. Supersedes the earlier estimate of 3 sites."
owner: frankA
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

### Where the "3" came from, and why it looked corroborated

Worth recording, because the wrong number survived being quoted between three
sessions. `feature-sysutils-delphi-exception-api-gaps-found-by-rtl-generics`
(done, historical — do not edit it) states two counts as separate findings:
*"`EArgumentOutOfRangeException` — 3 sites in `defaults`"* and
*"`Exception.CreateRes(@ResourceString)` — 3 sites"*. Two symbols, two headings,
the same figure: that reads as corroboration.

It is not. Both symbols occur **7** times in `generics.defaults.pas`, on *the
same seven lines* — 2960, 3049, 3075, 3078, 3182, 3218, 3221 — because each line
spells both:

```pascal
raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);
```

So there were never two independent counts to agree with each other. One
measurement was recorded under two headings and inherited a second heading's
worth of apparent confirmation. And a count that stops at 3 where the truth is 7
is the shape of an **error-limited compile**, not of a grep — the same instrument
confusion that produced the "5" elsewhere in this thread.

The corrected figures above were taken by listing the matching lines rather than
counting them, which is why they are quotable.

## Resolved 2026-08-28 (frankA)

**A `resourcestring` section now declares initialised string STORAGE instead of
registering literal aliases** — which is what FPC's runtime-replaceable
resourcestring is, and what makes `@S` legal. Parser-only; no `lexer.inc`, no
Track A file, nothing in `ir*.inc` or the backends.

### The fix was one arm of a double case that had already been fixed on the other arm

`ParseConstSection`'s TYPED arm carried this exact defect until
`bug-p-a-typed-string-constant-cannot-be-assigned`: `const S: string = 'x'` was a
StrConst registration with no storage, and **the tell was the same
name-resolution diagnostic** — `S := 'b'` answering *undefined variable (S)*
rather than "cannot assign", because there was no storage to be read-only. That
session fixed the typed arm. The untyped/`resourcestring` arm was its sibling and
stayed broken for exactly as long as the two mechanisms existed separately —
`devdocs/dev/normalise-dont-special-case.md`'s "if you fix a bug on one arm of a
double case, grep for the sibling before closing the ticket", demonstrated at a
distance of one ticket.

So the fix is a shared `DeclareInitialisedStringVar` (storage + a kind-1 pending
init), called by BOTH arms, rather than a second copy of the same four lines.

### What changed

| file | change |
| --- | --- |
| `pasparser_decl.inc` | `DeclareInitialisedStringVar` helper; `BareStringKind`; typed arm routed through the helper; the three untyped registration points honour `isResStr` |
| `pasparser_decl/proc/prog.inc` | `ParseConstSection` gains `isResStr: Boolean` — 10 call sites, the 3 `resourcestring` ones pass `True` |
| `lib/rtl/sysutils.pas` | comment-only: it claimed call sites were blocked, which stopped being true here (lane note below) |

**A parameter, not a global.** The function's own comments record a state-leak
bug (`bug-pascal-class-const-visibility`, the crtl-autopull leak) caused by a
global here needing stack discipline against a nested on-demand unit compile
firing mid-value. A parameter cannot leak that way.

### Two arms that would have been missed, and how

1. **A one-character resourcestring.** `SComma = ','` was collapsing to a *Char*
   const. That arm did **not** error in the baseline — it took an address
   happily and read garbage through it, which is strictly worse than the
   diagnostic the ticket is named for. Now excluded from the Char collapse and
   pinned in the test.
2. **The concatenation form.** `S = 'a' + 'b'` registers at a different site from
   the plain literal. Both are in the test.

### Two wrong turns, both found by measuring rather than reasoning

- **Blamed ambient `LastTypeRecId`.** `AllocVar` does read ambient `LastType*`
  state, so a stale record id was a clean story — and rebuilding disproved it
  (bss unchanged at 8.4 MB). The guard is kept because the dependency is real and
  undefended, but it was **not** the bug. Recorded because the ticket would
  otherwise carry a plausible wrong root cause, which is the failure this repo
  has a playbook about.
- **Hardcoded `tyString`.** Bare scalar `string` is **`tyAnsiString`** — managed
  is the default model; `tyString` is the legacy frozen one behind
  `-uPXX_MANAGED_STRING`. So `^string` (= `^AnsiString`) pointed at a frozen
  buffer: an 8.4 MB bss for one string, an empty read, then a segfault on deref
  — the value right and only the SHAPE wrong, far from the cause. Fixed by
  adding `BareStringKind` and routing **both** `ParseTypeKind` and this path
  through it, so the two cannot drift. Copying the condition would have
  reproduced this bug's own shape one level up.

### Verification

- **Baseline first.** `test/test_resourcestring_addressable.pas` fails on
  `pinned` with `undefined variable (SPlain)` — the ticket's symptom — and
  matches FPC on all 7 rows after.
- **Corpus, attributed cleanly.** `pinned` is NOT the right baseline here (it
  predates other landed-but-unpinned fixes and dies at `:2205` on an unrelated
  wall). Rebuilt this same tree with the change stashed:
  `generics.defaults.pas` **before: `:2960` `undefined variable
  (SArgumentOutOfRange)`** — the first of the seven `CreateRes` sites —
  **after: `:3231`**, the already-ticketed Delphi-mode `specialize` ordering
  defect (wall 6, parked). ~271 lines, past all seven sites.
- Ordinary consts unaffected: `const C = 'z'` is still a Char (`Ord` = 122, set
  membership TRUE), `'a' + 'b'` still folds — verified against FPC.
- `make compiler/pascal26`: `converged after 1 round(s)`, `ea11fad25feb`. The
  compiler's own sources are dense in const sections, so self-host is a real
  regression signal here.
- Test wired into the Makefile, pinning **both** directions: the address works,
  and a one-char resourcestring stays a string.

### Divergence recorded, not hidden

pxx accepts `SFoo := 'x'`; FPC refuses it (*Variable identifier expected*).
That is CLAUDE.md's "we accept a form FPC rejects" row — no compiling FPC program
can observe it — so it went to `devdocs/dev/pascal-dialect-divergences.md`, with
the note that it must never appear in an FPC-oracled test (the oracle dies on
that line, and a dead oracle looks like an agreeing one).

### Lane note

`lib/rtl/sysutils.pas` is a **Track B** file and I hold P. The edit is
comment-only: that comment asserted *"CALL SITES ARE BLOCKED TODAY"*, which this
change falsified, and leaving it would have been the same stale-copy failure as
the "3 sites" figure this session spent a thread correcting. No B ticket was
held and `lib/` had no in-flight edits. Declared rather than done quietly.

## Log
- 2026-08-28 — resolved, commit c9cf8c457.
