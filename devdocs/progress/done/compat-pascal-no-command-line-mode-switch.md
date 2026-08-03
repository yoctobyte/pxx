---
summary: "FPC's -Mdelphi / -Mobjfpc command-line mode switch has no pxx equivalent — the dialect can only be set with a {$MODE} directive in the source. Real projects set it in the build, not the file, so their sources carry no directive and pxx silently compiles them in the wrong dialect"
type: compat
track: P
prio: 45
status: done
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

## Resolution 2026-08-03 (claude-AC@opus5)

`-M<mode>` implemented in `compiler.pas`'s option loop. Same policy as the
`{$MODE}` directive: only `delphi` (and `delphiunicode`) changes behaviour, every
other mode name maps to the default dialect and is **accepted but inert**, so a
build script's `-Mtp` / `-Miso` does not die on an unknown option. It also flips
`NestedComments`, which is part of what delphi mode means.

### The implementation note above was WRONG — worth recording

It claimed `DelphiMode` is reset per source, so a command-line default would have
to seed the reset rather than assign once. Checked instead of trusted:
`PasInitDefines` has exactly **one** call site, `compiler.pas:206`, and the option
loop starts at 207 — it runs once per invocation, *before* options. So a direct
assignment in the option handler is correct and nothing clobbers it. A source
`{$MODE}` still wins for free, because directives are honoured later during
lexing. No new global either, which also avoids the `MAX_GLOBFIX` landmine.

The caution cost nothing here, but the note would have sent the next reader down
a longer path than the problem needed.

### Verified against FPC 3.2.2, same flag

| invocation | pxx | fpc |
| --- | --- | --- |
| (no flag) | `7 1` | `7 1` (`-Mobjfpc`) |
| `-Mdelphi` | **`42 4`** | **`42 4`** |
| `-Mobjfpc` | `7 1` | `7 1` |
| `-Mtp` (inert) | `7 1` | — |
| source `{$MODE DELPHI}` + `-Mobjfpc` | `42 4 7 3 10` (directive wins) | — |

`test/test_pascal_mode_switch_cli.pas` (**new**, gated) carries **no** mode
directive — which is how real Delphi projects ship — so the flagged and unflagged
runs must produce *different* output. If the switch were ignored both would print
`7 1` and the test fails; it cannot pass by accident.

### Found while writing the test, filed separately

[[compat-pascal-directive-in-comment-ignores-nested-comments-off]] — with nesting
off, pxx still special-cases a `{$...}` sequence inside a brace comment where FPC
lets the closing brace end the comment. Lax direction (pxx accepts what FPC
rejects), so it is a compat item, not a bug. The first two drafts of the new test
tripped over it — the second one in the very sentence describing the hazard.

## Log
- 2026-08-03 — filed and resolved the same day.
- 2026-08-03 — resolved, commit HEAD.
