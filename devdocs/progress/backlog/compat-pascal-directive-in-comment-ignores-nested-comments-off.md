---
summary: "With nested comments OFF (delphi mode), a {$...} sequence inside a brace comment does not end the comment in pxx, but does in FPC. Lax direction — pxx accepts sources FPC rejects"
type: compat
track: P
prio: 25
---

# `{$...}` inside a brace comment survives `{$NESTEDCOMMENTS OFF}` in pxx

> **TRIED AND REVERTED 2026-08-19 — read before attempting it.** The one-line
> fix is real, it is in the right place, and **it breaks the self-build.** Do not
> spend the session rediscovering that; see "Why the obvious fix cannot land"
> below. Left in `backlog/`; nothing of it is applied.

- **Type:** compat (FPC parity, Pascal lexer) — **Track P**
- **Found:** 2026-08-03 by `claude-AC@opus5` while writing the `-Mdelphi` test
  ([[compat-pascal-no-command-line-mode-switch]]) — the first two drafts of that
  test compiled under pxx and were rejected by FPC, which is what exposed it.

## Measured, delphi mode (nested comments off) on both compilers

```pascal
program dc;
{ outer {$DEFINE FOO} still outer }
begin writeln('compiled'); end.
```

| construct | FPC `-Mdelphi` | pxx `-Mdelphi` |
| --- | --- | --- |
| plain nested brace — `{ outer { inner } still outer }` | reject | reject — **agree** |
| brace **directive** — `{ outer {$DEFINE FOO} still outer }` | reject | **accept** |

So the plain nesting rule is right; the divergence is specific to a `{$`
sequence. With nesting off, FPC treats the directive's closing brace as ending
the enclosing comment and then parses the trailing prose as code. pxx keeps
scanning, apparently special-casing `{$` in the comment scanner regardless of
`NestedComments`.

The same applies to a `{$MODE ...}` written inside a comment, which is how this
was hit: prose *about* directives is a natural thing to write in a file header.

## Severity: low, and in the safe direction

pxx is **more permissive** — it accepts sources FPC rejects, never the reverse.
Nothing miscompiles and no value is wrong; a file that builds under pxx may fail
under FPC, which is the direction this project already accepts by default
(`CLAUDE.md`: pxx's dialect is deliberately lax, FPC-parity strictness lives
behind per-feature strict flags). Hence prio 25 rather than a `bug-` ticket.

It matters mainly for **corpus work**: a real Delphi codebase whose comments
contain directive text compiles here and would not under the reference compiler,
so "it builds with pxx" is weaker evidence than it looks for that file.

## Fix shape

In the brace-comment scanner, the `{$` special case should apply only when
`NestedComments` is on. Behind `--strict-fpc` if flipping it unconditionally
turns out to break existing sources — check `lib/**` and the Pascal corpora
first, since header comments discussing directives are common and this has been
the lenient behaviour for the project's whole history.

## Gate

The `{ outer {$DEFINE FOO} still outer }` case above is rejected in delphi mode
and still accepted with nested comments on, matching FPC in both; `lib-test` and
the Pascal corpora still build.


## 2026-08-19 — the obvious fix cannot land, measured

The divergence is exactly where this ticket says it is. Two sites in
`compiler/lexer.inc` (the active scanner in `SkipSpace`, and the
inactive-conditional-branch scanner above it) nest the comment on an inner
open-brace when

```pascal
(NestedComments or ((SrcPos < Length(Source)) and (Source[SrcPos + 1] = '$')))
```

— the `$` arm fires **regardless of the switch**, which is the whole bug. Both
sites carry a comment saying it is deliberate, "lets prose mention conditional
directives inside comments safely".

Dropping that arm gives exact FPC parity in delphi mode and changes nothing
under `NestedComments` (which **defaults to True** here, the real FPC default —
the "off (default) keeps the historic flat scan" note next to it is stale). It
also stops the compiler compiling itself:

```
pascal26:8534: error: unexpected character
```

**69 brace comments in `compiler/**` open by quoting a directive** — the first
one reached is `ir.inc`'s range-check note, which opens `{ ` and then a `{$R+}`
on the same line — plus 4 more in `lib/**`. Every one of them is a comment whose
brace count only balances because of the `$` arm. So the tolerance is not
decorative; this codebase is written on top of it.

That makes this a **dialect decision, not a lexer fix**, and it belongs with the
house rule in CLAUDE.md: *"PXX's own dialect stays deliberately lax by default;
FPC-parity strictness lives behind per-feature strict flags."* The parity
behaviour wants a `--strict-comments`-style flag that the conformance sweep
turns on, leaving the default lax — and landing that means the flag AND leaving
all 69 sites alone, which is a different and larger job than this ticket
describes.

### Method note

The first pass of this measurement claimed **zero** in-tree reliance and was
wrong: the grep was `grep -rn "{ [^}]*{\$"` in double quotes, where `\$`
collapses to `$` and the pattern anchors to end-of-line, so it matched nothing
and looked like a clean bill of health. The self-build caught it one build
later. Single quotes (`'{ *{\$'`) give the real 69.
