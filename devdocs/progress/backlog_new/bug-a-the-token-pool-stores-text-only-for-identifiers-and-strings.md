---
track: A
prio: 60
type: bug
blocked-by: []
status: new
owner: ""
found: 2026-08-30
found-by: frank-optimize, doing bug-a-a-failed-expect-prints-a-raw-dump-with-no-error-prefix-and-no-source-path
summary: "Every lexer stores token text for tkIdent and tkString only; keywords, punctuation, operators and numbers get SOffset := 0. That if/else is hand-copied across eleven lexers. So the `near:` window under EVERY diagnostic in the compiler prints the identifiers and silently discards the syntax -- `near: begin x >>> end` for `x := (1 ;` -- and no diagnostic can name an offending keyword. Sized: 3.24 MiB of token text against a fixed 8 MiB STRING_CAP, 40.5%, so this is a mechanical change to eleven files, not a pool redesign."
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
