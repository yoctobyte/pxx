---
track: A
prio: 30
type: bug
status: working
blocked-by: []
owner: frank-optimize
summary: "A failed Expect() writeln's `Expected: X, but got:  (Kind: 57, Line: 2)` -- a token ORDINAL, no source path, and no `error:` prefix, so anything keying on `error:` does not see it as an error at all. lexer.inc:2838, shared by every frontend. Reached from C by an unclosed initializer followed by a real declaration."
---

# A failed `Expect` prints a raw dump: no `error:` prefix, no source path, a token ordinal

- **Track A** — `compiler/lexer.inc:2838`, shared by every frontend.
- **Found:** 2026-08-30 by frankC, finishing
  `bug-c-an-unclosed-initializer-list-reports-the-next-error-instead-of-itself`.
  It is the one shape of that ticket that its fix could not reach, and the
  reason is that it is not that bug.

## The measurement

Compiler `e07289bc4e9c` (self-host fixedpoint at HEAD).

```c
char *p[] = { "a", "b"
int main(void){return 0;}
```
```
Expected: }, but got:  (Kind: 57, Line: 2)
```

gcc: `error: expected '}' before 'int'`.

Four things wrong with one line of output:

1. **No `error:` prefix.** Every other diagnostic in this compiler is
   `pascal26:<line>: error: <text>`. Anything that greps for `error:` — a build
   script, a test recipe, a harness classifying a run — does not see this as an
   error. The compile does fail, so the exit code is right; only the *text* lies.
2. **No source path.** The reader is not told which file.
3. **`Kind: 57` is an internal token ordinal**, meaningful only against
   `TTokenKind`'s declaration order, and it moves whenever a token is added.
4. **`but got: ` is empty** — the offending token's `SVal` is blank for a
   keyword, so the one field that would have named the culprit (`int`) prints
   nothing. The ordinal is there *instead of* the name, not beside it.

## Why it is Track A and was not fixed under C

`Expect` is in `compiler/lexer.inc` — shared by Pascal, C, NilPy, Rust, Zig and
asm. Every frontend that calls `Expect` and does not get what it asked for
prints this. Fixing it under Track C would be editing A's file; per the lane
rule it is filed instead.

**It is also the right place to fix it.** The tempting local repair is to have
each caller pre-check and raise its own message — which is how `cparser.inc`
came to spell one rule six ways in the ticket above. One raise site, one wording.

## What it is NOT — checked, because the two look identical from outside

This is **not** the unterminated-construct bug. That one is fixed: an unclosed
brace run that reaches **EOF** now refuses everywhere with
`unterminated C construct: end of file before its closing brace`. Verified on
seven shapes.

The case here never reaches EOF. `CBlockContinues` ends the element loop, the
loop `Break`s on a token that is neither a comma nor a close brace, and the raw
`Expect(tkEnd)` then fires against a perfectly ordinary `int` token on line 2.
So the parser's *detection* is correct and correctly located — only the
**rendering** is broken, and that is a different defect with a different owner.

Recorded because the two shapes are one character apart in the source and
produce completely different failures; a future reader who assumes the
unterminated fix covers this will be wrong.

## Suggested fix

Route the failure through the same `ErrorAt` path every other diagnostic uses:
`pascal26:<line>: error: expected '}' before '<token text>'`, naming the token by
its **spelling** (its source text, which the lexer has) rather than its ordinal.
Keep the ordinal only behind a debug flag, where it is genuinely useful.

## Gate

Track A's: `make compiler/pascal26` to fixedpoint + the repro above producing an
`error:`-prefixed, path-qualified message. Note the blast radius — every
frontend's `Expect` failures change text at once, so existing tests that grep for
the old raw wording must be re-checked. `grep -rn "Expected: " test/ Makefile`.

## Resolution (2026-08-30, frank-optimize)

Fixed at the `Expect` call site only — `WriteDiagSourceFile` is untouched (it was
concurrently held by frankC for
`feature-c-diagnostics-name-the-module-they-are-in`, and the two changes turned
out to be disjoint: this one alters the TEXT on a path that already ran).

```
before:  Expected: }, but got:  (Kind: 57, Line: 2)
         pascal26:2: error: unexpected token
           near:    a  b >>>  main

after:   pascal26:2: error: expected '}'
           near:    a  b >>>  main
```

The raw line was a second output path that skipped the first one: `Error` already
printed the prefix, the `in:` path and the `near:` window one line below it. So
the fix is to delete the second path and give the first one the words, per
`normalise-dont-special-case.md` — not to teach the raw line to print a prefix.

All four items in "The measurement" are addressed. Prefix and path come free from
`Error`. The ordinal moves behind `PXXDBG=a.expect:*`, which now also reports the
kind that was WANTED — something the old line never carried:

```
$ PXXDBG='a.expect:*' ./compiler/pascal26 unclosed.c /tmp/u
PXXDBG a.expect want=6 got=57 line=2
pascal26:2: error: expected '}'
```

### Item 4 was diagnosed backwards, and that is where the real bug was

This ticket said `but got: ` is empty because "the ordinal is there *instead of*
the name". It is not: **there is no name to print.** Every lexer stores token text
for `tkIdent` and `tkString` only — an if/else hand-copied across eleven lexers —
so a keyword, operator or number has no recoverable spelling. Measured both ways:

```
x := (1 foo);   ->  but got: foo     identifier: named
x := (1 ;       ->  but got:         ';': blank
```

The field populates for the tokens a reader could already identify and blanks for
the ones they could not. So the message here names the token only when the text
exists, and omits the clause otherwise, rather than printing an empty field: an
omitted clause says "not recorded", an empty one reads as "nothing there".

Recovering the missing spellings is filed as
**`bug-a-the-token-pool-stores-text-only-for-identifiers-and-strings`** [A, p60] —
higher than this ticket, because the same root cause degrades the `near:` window
under **every** diagnostic in the compiler (`x := (1 ;` renders
`near: begin x    >>>  end`, dropping `:=`, `(`, `1` and `;`), and because the
sizing came out cheap: 3.24 MiB of token text against a fixed 8 MiB `STRING_CAP`.

That ticket also carries the refutation of the tempting fix, which belongs on the
record here too: a kind-to-spelling table cannot work, because
`Expect(tkEnd, '}')` in `cparser.inc` and `Expect(tkEnd, 'end')` in
`pasparser_stmt.inc` are one kind with two spellings. `Expect`'s `name` parameter
exists for exactly that reason.

### Blast radius: nil, measured by fragment and then by kind

| fragment | Makefile | test/ | *.expected |
| --- | ---: | ---: | ---: |
| `Expected: ` | 6 | 30 | 0 |
| `but got` | 3 | 14 | 0 |
| `Kind: ` | 0 | 14 | 0 |

All six Makefile hits are `#` comments; zero `{%FAIL}` directives; the test/ hits
are file-header prose describing what a bug used to print. Nothing asserts on the
old text, so no test needed updating with this commit.

### Reachability check

The hazard in changing a diagnostic is altering *when* a path runs rather than
what it prints — invisible to every test that has an answer. Falsifiable check
used: `pascal26:<line>: error:` was ALREADY present in every repro before this
change, so the line appearing or disappearing anywhere would mean reachability
moved. Verified unchanged on three shapes (keyword, identifier, punctuation),
same line numbers, one such line each, before and after.

### Gate

`make compiler/pascal26` -> converged after 1 round(s), `1432cdb1401a`;
`tools/gate.sh quick` -> GREEN 7/7.
