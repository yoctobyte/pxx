---
summary: "With nested comments OFF (delphi mode), a {$...} sequence inside a brace comment does not end the comment in pxx, but does in FPC. Lax direction — pxx accepts sources FPC rejects"
type: compat
track: P
prio: 25
---

# `{$...}` inside a brace comment survives `{$NESTEDCOMMENTS OFF}` in pxx

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
