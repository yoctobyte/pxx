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
