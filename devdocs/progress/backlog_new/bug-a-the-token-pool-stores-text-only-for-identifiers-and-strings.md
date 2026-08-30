---
track: A
prio: 25
type: bug
blocked-by: []
status: backlog_new
owner: ""
found: 2026-08-30
found-by: frank-optimize, doing bug-a-a-failed-expect-prints-a-raw-dump-with-no-error-prefix-and-no-source-path
summary: "RE-SCOPED 2026-08-30 after an attempt: this is NOT eleven mechanical lexer edits. SOffset/SLen is an OVERLOADED channel, not a text field -- for tkInteger, SLen>0 MEANS 'wider than Int64', so giving ordinary tokens their text makes every integer literal promotable and `writeln(42)` fails to compile. A correct fix needs a SEPARATE span channel, i.e. new parallel arrays in defs.inc, before any lexer is touched. Original finding stands: every lexer stores token text for tkIdent and tkString only; keywords, punctuation, operators and numbers get SOffset := 0. That if/else is hand-copied across eleven lexers. So the `near:` window under EVERY diagnostic in the compiler prints the identifiers and silently discards the syntax -- `near: begin x >>> end` for `x := (1 ;` -- and no diagnostic can name an offending keyword. Sized: 3.24 MiB of token text against a fixed 8 MiB STRING_CAP, 40.5%, so this is a mechanical change to eleven files, not a pool redesign."
---

# The token pool stores text only for identifiers and strings

## What every diagnostic in this compiler is currently printing

`lexer.inc` describes its `near:` window in-source as *"the difference between a
findable error and an unfindable one"*. Measured at `1432cdb1401a`:

```
C:       char *p[] = { "a", "b"   /   int main(void){return 0;}
  near:    a  b >>>  main                '{', ',' and 'int' render EMPTY

Pascal:  x := (1 ;
  near:  begin x    >>>  end             ':=', '(', '1' and ';' render EMPTY
```

It is printing the identifiers and discarding the syntax — that is, dropping
precisely the characters a syntax error is usually about. **Nobody has noticed
because it still looks like output.**

This is not the Expect path, or the C frontend, or one message. It is every
`near:` window under every diagnostic in every frontend, and it has been this way
for the whole life of the code.

## Cause, and it is one hand-copied if/else

```pascal
if (k = tkIdent) or (k = tkString) then
  begin ...copy into TokChars, set SOffset/SLen... end
else
  begin Tokens[TokCount].SOffset := 0; Tokens[TokCount].SLen := 0; end;
```

Reproduce the census with `grep -ln "SOffset := 0" compiler/*.inc`. **Eleven
lexers** carry that same else-branch: `clexer` `pylexer` `rlexer` `zlexer`
`alexer` `blexer` `elexer` `flexer` `glexer` `llexer`, plus Pascal's in
`lexer.inc` itself.

It is a defensible space optimisation — store text only where the text is not
implied by the kind — and it was almost certainly right when written. What
changed is that the same pool later became the source for **diagnostics**, where
the kind does not imply the text a *reader* needs to see. Nothing revisited the
branch when its second consumer arrived.

## The consequence the parent ticket got backwards

`bug-a-a-failed-expect-prints-a-raw-dump-with-no-error-prefix-and-no-source-path`
proposed naming the offending token *"by its spelling (its source text, which the
lexer has)"*. **The lexer does not have it.** That ticket's own repro offends on
`int`, a keyword, which is exactly why its `but got: ` printed empty. Its
diagnosis — "the ordinal is there *instead of* the name" — was wrong: there was
no name to print.

Measured, both directions:

```
x := (1 foo);   ->  Expected: ), but got: foo (Kind: 1, Line: 4)     identifier: named
x := (1 ;       ->  Expected: ), but got:  (Kind: 78, Line: 4)       ';': blank
```

So **the field populates for the tokens a reader could already identify and goes
blank for the ones they could not.** That is worse than having no field, because
a blank reads as "nothing there" rather than "not recorded" — and it is the same
shape as the instrument problem in the sizing below: the check is present exactly
where it is least needed.

## Do NOT fix this with a kind-to-spelling table

The cheap-looking fix is a `TTokenKind` -> text table. It is wrong by
construction here and one grep settles it, which is why the grep is in this
ticket rather than an argument:

```
cparser.inc:3271         Expect(tkEnd, '}');
pasparser_stmt.inc:2832  Expect(tkEnd, 'end');
```

One kind, two spellings, because kinds are shared across frontends and their
words are not. A table would confidently print the other language's keyword —
right in whichever frontend you tested, wrong in the rest, and silent about it.

This is `devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md` in a single
grep: share the AST and the IR, duplicate the parser and lexer per language. A
kind-to-spelling table is a shared *parser* helper wearing a diagnostics hat.
Note that `Expect`'s `name` parameter already exists for exactly this reason —
only the caller knows the language's word for the **expected** token. The gap is
that there is no equivalent for the **actual** one.

## The fix, and its size — measured, because the obvious measurement is wrong

Store `SOffset`/`SLen` for every token, not just identifiers and strings.
Language-agnostic: it repairs all eleven frontends and every `near:` window at
once, and it lets `Expect` (and anything else) name the offending token in the
user's own characters.

The question that decides whether this is mechanical or a redesign is whether the
text fits `STRING_CAP`, a **fixed** 8 MiB whose exhaustion is a hard
`Error('token char pool overflow')`. Measured over `compiler.pas` + every `.inc`
— the largest TU in the repo, and a generous over-count because a real build
excludes some includes by `{$ifdef}`:

| | bytes | |
| --- | ---: | --- |
| raw source | 10,630,888 | 10.14 MiB |
| whitespace stripped | 7,882,365 | 7.52 MiB | **<- ARTEFACT, see below** |
| **comments AND whitespace stripped** | **3,398,931** | **3.24 MiB** |
| `STRING_CAP` | 8,388,608 | 8.00 MiB, fixed |
| headroom | 4,989,677 | **40.5% used** |

**So: no pool redesign. Eleven lexers plus a test.**

### Both figures are here on purpose — read this before re-measuring

The 7.52 MiB row is an **artefact and it nearly killed this ticket.** At 94% of a
fixed cap, the honest conclusion would have been that `STRING_CAP` must first
become a dynamic buffer (the `DbgBuf` treatment from
`bug-a-g-with-o2-or-o3-overflows-the-dwarf-buffer-on-compiler-pas`, same day),
making this a two-stage job that would have been parked at that price.

The error was measuring a **proxy** for the quantity — source bytes — instead of
the quantity, token bytes. Comments never become tokens, and **this repo is ~68%
comment bytes**, so the proxy was 2.3x the truth and pointed at the opposite
conclusion. The next person sizing anything against `STRING_CAP` will reach for
source bytes too; that is why the wrong row is kept rather than tidied away.

The general form, which cost this fleet four incidents in one day across three
agents: **an alarming measurement earns a second instrument, not a ticket.** Not
more care — care is what produced the first reading. Change the instrument.

## Scope, ownership and the one hazard

- Eleven lexer files, **including `clexer.inc`** — Track C's lane. Sequence with
  whoever holds it; the change is the same three lines in each file, so it is
  splittable per lexer if that helps.
- `lexer.inc` is A/P shared, and the Pascal lexer's copy lives there.
- **The hazard is silent success.** Nothing currently *fails* because of this, so
  a partial fix produces output that looks equally plausible. Gate it on the
  observable, not on the suite: `near:` for `x := (1 ;` must render
  `begin x := ( 1 >>> ; end` and not `begin x    >>>  end`. A test asserting that
  window's exact text is the deliverable that keeps it fixed — there is currently
  no test anywhere on `near:` content, which is how it stayed broken.

## Gate

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick`, plus the `near:`
assertion above on at least one Pascal and one C repro. Cross-frontend breadth is
Track T's sweep.

## RE-SCOPED after an attempt (2026-08-30, frank-optimize) — read this before starting

**The fix in "The fix, and its size" above is wrong, and this ticket is not
eleven mechanical lexer edits.** I implemented the Pascal slice, and it fails in
a way that invalidates the approach rather than the implementation. Reverted; the
tree is clean and the binary is byte-identical to the pre-attempt fixedpoint
(`3d6768580af0`), which is how the revert was confirmed rather than by `git`.

### What went wrong: SOffset/SLen is an overloaded channel, not a text field

The ticket assumed the pool holds "the token's text, where the lexer bothered to
store it". It does not. It is a **per-kind channel whose meaning changes with the
kind**, and two of those meanings are carried by *emptiness itself*:

| kind | what the pool holds | what EMPTY means |
| --- | --- | --- |
| `tkIdent` | the NAME, which is not always the span (`&String` stores the bare name) | unreachable |
| `tkString` | the DECODED value, not the quoted source | a legitimately empty string `''` |
| `tkInteger` | the digit TEXT, set **only** when the literal exceeds Int64 | fits in Int64 |

That last row is the killer, and it is asserted in the consumer, not the lexer —
`pasparser_expr.inc:5738`:

```pascal
if Tokens[TokPos - 1].SLen > 0 then
begin
  ASTSOffset[node] := Tokens[TokPos - 1].SOffset;
  ...
  ASTTk[node] := Ord(tyInt64);
```

**`SLen > 0` on an integer token IS the flag for "wider than Int64".** Give every
token its text and every integer literal becomes a promotable wide int:

```
$ pxx triv.pas          program t; begin writeln(42); end.
pascal26:4: error: promotable int: runtime helper PXXPromoFromStr not found
```

`writeln(42)` stops compiling. Measured, not predicted.

The same file already knew about the collision and said so two lines further on
— *"indistinguishable from a char literal's char-pool span"* — so this is a
**third** consumer of the same overloaded emptiness, documented in passing and
never named as a design fact.

### The empty-string trap, which is the same shape one layer up

The first attempt filled `CurTok.SVal` when it was empty. `tkString`'s SVal is
legitimately empty for `''`, so every empty string literal in the source became
the two-character text `''`: `PXX_CONFIG` was read as a filename of two
apostrophes, and the inline assembler was handed `''` where it wanted an integer.

**Round one of the self-host compiled clean; round two caught it.** An FPC-seeded
gen-1 built and ran fine. That is worth keeping: this class of bug is invisible to
a single build and visible to a fixedpoint, which is precisely the argument for
`make compiler/pascal26` being the gate rather than a build.

### What a correct fix looks like

**A separate channel.** Record the source span in new parallel arrays
(`TokSrcOff` / `TokSrcLen`, or two new `TRawToken` fields), leave `SOffset`/`SLen`
and every sentinel exactly as they are, and point the diagnostics — `near:`,
`Expect`'s "before X" — at the new arrays only.

That is still the right fix and the value argument in this ticket is unchanged.
But it changes the schedule in two ways that matter:

1. **It needs `defs.inc` FIRST.** `Tokens` is `array of TRawToken` and every
   parallel token array (`TokPackRecords`, `TokQChecks`, ...) is declared there.
   There is no file-level `var` in any include — all globals live in `defs.inc` —
   so there is no route to a new array that avoids it. **The eleven lexers cannot
   start until that lands.** `defs.inc` was held by frankwasm for the UTF-16
   string model at the time of writing.
2. **The per-lexer work is no longer uniform, so "mechanical" is wrong twice
   over.** The sentinel above is Pascal-side (`pasparser_expr.inc`). Each
   language must be re-checked for its own overloaded uses of pool emptiness
   before its lexer is changed — C keeps its own attribute flags in
   `CAttrFlags`, and the other nine are unaudited. Slicing per lexer is still
   right; each slice just carries an audit rather than a copy-paste.

### What survives unchanged

The problem, the value, the p60 ranking, the refusal of a kind-to-spelling table,
and the sizing (3.24 MiB against a fixed 8 MiB `STRING_CAP` — the new arrays are
indices into the same source, so they add no pool bytes at all; if anything the
sizing is now generous).

And the gate is unchanged and is still the deliverable: `near:` for `x := (1 ;`
must render `begin x := ( 1 >>> ; end`. The attempt did produce exactly that
before it was reverted, so the observable is known to be reachable:

```
before:  near:  begin x    >>>  end
during:  near: ; begin x := ( 1 >>> ; end .        <- and Expect gained
                                                      "expected ')' before ';'"
```

That is the payoff, measured. It just cannot be bought at the price of the
integer-literal sentinel.

## Slice 1 of 12 landed: `defs.inc` channel + the Pascal lexer (2026-08-30, frank-optimize)

```
before:  pascal26:17: error: expected ')'
           near:  begin x    >>>  end
after:   pascal26:17: error: expected ')' before ';'
           near: ; begin x := ( 1 >>> ; end .
```

`TokSrcOff`/`TokSrcLen` in `defs.inc` (beside the other parallel token arrays,
grown in lockstep by `EnsureTokCapacity`), filled by the Pascal lexer, read by
`WriteTokenContext` and `Expect`. Sentinels untouched — which is the whole point,
and is asserted rather than asserted-to-be-true: **twelve programs across
generics, properties, wide literals and nil-checks compile to byte-identical
binaries** against a control built from the same HEAD without the change. The
generics corpus is in there deliberately, because it is what moved under the
rejected approach.

Other frontends are unchanged, on purpose: `TokSrcLen` is 0 for tokens their
lexers append, and both consumers fall back to `SOffset`/`SLen`, so C still
renders `near:    a  b >>>  main` until its slice lands. Ten lexers to go.

### The observable is a test now, and it was shown to fail first

`test/test_diag_near_window_fail.pas` + two rows in `test-core` assert the exact
`near:` text and that `Expect` names `';'`. Run against the pre-change binary
both fail, and the guard prints the difference itself:

```
expect_same: MISMATCH [test_diagnear26]
-  near: ; begin x := ( 1 >>> ; end .
+  near:  begin x    >>>  end
```

### The pool nearly ate its own cap, and the first number was a proxy again

`STRING_CAP` is a FIXED 8 MB and overflowing it is a hard `Error`. Storing every
spelling unconditionally measured **7,221,196 bytes — 86% of cap**, leaving 1.1 MB
of headroom on the largest Pascal TU in the repo. My earlier sizing said 3.24 MiB
and 40%; it was counting *spans* and forgetting the pool already holds SVal, so
the true cost was the sum of both. Same failure as the 7.52 MiB row above, one
level down: **I sized the addition instead of the total.**

Fixed by sharing rather than by raising the cap: when a token's spelling is
byte-equal to the SVal already written — which for an identifier it almost always
is — `TokSrcOff`/`TokSrcLen` point at those same bytes instead of a copy.

| | bytes | % of cap |
| --- | ---: | ---: |
| before this feature | 3,219,348 | 38.4% |
| naive, every spelling copied | 7,221,196 | 86.1% |
| **sharing identical bytes** | **4,261,414** | **50.8%** |

Net cost ~1.0 MB, headroom 3.9 MB. Measured with `PXXDBG=a.tokpool:*`, added in
the same commit precisely so the next person sizing against `STRING_CAP` reads
the pool instead of counting source bytes — twice now that proxy has pointed the
opposite way.

### Warning for the C slice specifically

`defs.inc` records that a FIXED cap is what sqlite's 257k-line amalgamation broke
before. C spellings on a TU that size are the case most likely to exhaust the
pool even with sharing, so **the C slice must measure `a.tokpool` on the
amalgamation before it lands**, and may need `STRING_CAP` to become dynamic
(the `DbgBuf` treatment from
`bug-a-g-with-o2-or-o3-overflows-the-dwarf-buffer-on-compiler-pas`) as its own
prerequisite. Do not assume Pascal's 50.8% generalises.

### Provenance correction

frankC and I independently found the same false premise and the same
`clexer.inc:834` — and then independently proposed the **same wrong fix**, because
we were both reading the pool as a text field. Two agents agreeing was evidence
the *problem* was real; it was not evidence the *solution* was, and it could not
have been: agreement cannot detect a shared premise. What separated them was an
attempt costing twelve seconds of build.

### Gate

`make compiler/pascal26` -> converged after 1 round(s), `379ffffc4151`;
`tools/gate.sh quick` GREEN 7/7; twelve-program emitted-code A/B identical; both
new assertions shown to fail on the pre-change binary.

## Slice 2 (NilPy) landed, and the ticket is RE-SCOPED (2026-08-30, frank-optimize)

```
NilPy, before:  near:   m  self  >>>   pass
NilPy, after:   near:  def m ( self ) >>>   pass
```

**The denominator was never eleven.** Pascal carried the compiler's own
diagnostics and NilPy is mainline with a gated suite and real users; those two
were the value and both are done. What remains is not a campaign:

| lexer | status |
| --- | --- |
| Pascal (`lexer.inc`) | **DONE** — slice 1 |
| NilPy (`pylexer.inc`) | **DONE** — slice 2 |
| C (`clexer.inc`) | **GATED** on the pool measurement below — do not start without it |
| `rlexer`, `zlexer` | X-tagged experimental: optional, never a prio, by CLAUDE.md's own rule |
| `blexer`, `elexer`, `flexer`, `glexer`, `llexer`, `alexer` | **opportunistic** — one line each, take one when you are already in that file for another reason |

**Prio dropped 60 -> 25 to match.** 60 was right when this was "every frontend's
diagnostics are broken"; the two that mattered are fixed, and leaving it at 60
would keep offering the ranker work whose value stopped after slice 2. The
coordinator may re-rank.

### Each remaining lexer is now one line

`RecordTokSpan(idx, startPos, endPos)` in `lexer.inc` is THE implementation —
pool write, byte-sharing, cap check, bounds clamp. A lexer's slice is: know where
its token began, and call it. That extraction is deliberate: writing the block
per lexer would have rebuilt the exact eleven-hand-copies situation this ticket
exists to repair. What stays per-language is deciding where a token starts and
ends — that is the lexer's own business
(`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md`: duplicate parsers,
share substrate; this is substrate).

NilPy shows the shape for a lexer whose emitter has many call sites: `PyEmitToken`
has **65**, and several are synthetic (the complex-literal expansion, the
inline-suite INDENT/DEDENT pair) with no source text at all. None were touched.
The span is taken where the scanner knows a real token began and finalised at the
top of the next iteration, and **only when the branch appended exactly one
token** — a multi-token expansion leaves `TokSrcLen` at 0 and the diagnostics fall
back, which is correct, because those tokens are not in the source.

### The C measurement: TAKEABLE, not taken — the file is not in this checkout

`library_candidates/` does not exist here (gitignored scratch; `SQLITE_SRC ?=
library_candidates/sqlite`, and the sqlite rows skip when it is absent). So the
number cannot be produced from this tree, and no estimate of it belongs in this
ticket — a guess at the quantity is what went wrong twice already.

What was done instead is to make it **one command** for anyone who has the file.
`PXXDBG=a.tokpool:*` was moved out of the Pascal lexer into `TokPoolReport`,
called at end of compile, so it reads the same number for **every** frontend:

```
$ PXXDBG='a.tokpool:*' ./compiler/pascal26 library_candidates/sqlite/sqlite3.c /tmp/o
PXXDBG a.tokpool bytes=... cap=8388608 pct=... tokens=... spellings=... other=...
```

Validated on what is here — Pascal `pct=52`, NilPy `pct=7`, small C `pct=1`:

**The decision rule for the C slice.** Run it on the amalgamation *before* the
slice, to get C's baseline. The slice adds roughly the TU's code bytes minus what
byte-sharing recovers; on Pascal the total landed at 52%. If C's post-slice
projection clears ~75%, the slice is schedulable. If not, `STRING_CAP` must
become dynamic first — the `DbgBuf` treatment from
`bug-a-g-with-o2-or-o3-overflows-the-dwarf-buffer-on-compiler-pas` — as its own
prerequisite ticket, and `defs.inc` records that a fixed cap is exactly what
sqlite's 257k-line amalgamation broke once already. **Pascal's 52% does not
generalise; do not assume it.**

One thing the measurement already shows, free: a C compile reports
`spellings=112715` even with `clexer` untouched, because it pulls Pascal RTL
units through `LexAppend`. That is the fallback working as designed — C's own
tokens contribute nothing to the new channel and its `near:` windows are
unchanged — but it means a naive reading of `spellings` on a C file is NOT C's
cost. Subtract the RTL's.

### Gate

`make compiler/pascal26` -> converged after 1 round(s), `c528c6cddda7`;
`tools/gate.sh quick` GREEN 7/7; three assertions (two Pascal, one NilPy) pass
and each was shown to fail against the binary from before its own slice.
