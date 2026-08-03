---
summary: "FPC's -Mdelphi / -Mobjfpc command-line mode switch has no pxx equivalent — the dialect can only be set with a {$MODE} directive in the source. Real projects set it in the build, not the file, so their sources carry no directive and pxx silently compiles them in the wrong dialect"
type: compat
track: P
prio: 45
---

# No command-line `-Mdelphi` / `-Mobjfpc`

- **Type:** compat (FPC parity, Pascal frontend) — **Track P**
- **Found:** 2026-08-03 by `claude-AC@opus5` while pinning the bare-own-name
  dialect split ([[bug-paramless-self-recursion-silent-result-read]]).

## What works and what does not

The `{$MODE DELPHI}` / `{$MODE OBJFPC}` **directives** work and are obeyed —
verified against FPC 3.2.2 in both modes, including the bare-own-name rule where
the two dialects genuinely disagree (delphi recurses, objfpc reads `Result`).
That half is now gated by `test_pascal_self_result_delphi.pas` and
`test_pascal_self_result_warn.pas`.

What is missing is the **command-line** form. FPC takes `-Mdelphi`, `-Mobjfpc`,
`-Mtp` etc.; pxx has no `-M` option and no `--mode=` equivalent
(`grep "'-M" compiler/compiler.pas` finds nothing).

## Why it matters more than a missing flag usually does

Real Delphi-targeting projects set the mode **in the build**, not in each source
file — that is what `-Mdelphi` is for, and it is why so much Delphi code carries
no `{$MODE}` line at all. Handed such a project, pxx compiles it in the default
objfpc-like dialect with no diagnostic, and the differences are the silent kind:
a bare paramless own-name read becomes a `Result` read instead of the recursive
call the author wrote. That is precisely the failure this repo has now paid for
twice, arriving through a different door.

## Implementation note

Not a one-liner. `DelphiMode` is reset per source in `lexer.inc:610` and only
ever set by the directive at `lexer.inc:1654`, so a command-line default has to
seed the per-source reset rather than assign once at startup — otherwise the
reset silently discards it. A source-level `{$MODE}` must still win over the
command line, matching FPC.

Worth taking the other FPC mode names at the same time (`-Mobjfpc`, `-Mtp`) even
if only delphi/objfpc differ in behaviour today, so build scripts do not fail on
an unrecognised option.

## Gate

`-Mdelphi` makes a directive-less source behave exactly as the same source with
`{$MODE DELPHI}` does — checked with the existing pair of self-result tests, whose
outputs differ between the modes (`42 4 7 3 10` vs `5 1 8 42 6 42 100`), so the
flag either takes effect or the test fails. A source `{$MODE}` overrides the flag.
