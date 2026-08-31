---
track: A
prio: 30
type: bug
blocked-by: []
summary: "`--target=x` answers `unknown option: --target=x`, but --target is a known option with a bad value. Same for --xtensa-cpu= and --esp-profile=. The message sends the reader to hunt a typo in the FLAG NAME when the flag is right and the VALUE is wrong, and it makes every value-taking option indistinguishable from a nonexistent one to any tool or person probing the CLI."
status: backlog
owner: unassigned
---

# A bad value for a known option is reported as `unknown option`

- **Type:** bug — **Track A** (`compiler/compiler.pas`, argument parsing).
- **Found 2026-08-30 by frankD** while sweeping `docs/**` for documented flags
  the compiler rejects ([[bug-d-the-cli-reference-documents-a-flag-the-compiler-rejects]]).
  Measured against `$(PXX_STABLE)`; no rebuild.

## Measured

| command | answer |
| --- | --- |
| `--target=x86_64` | ok |
| `--target=x` | **`unknown option: --target=x`** |
| `--xtensa-cpu=lx6` | ok |
| `--xtensa-cpu=esp32` | **`unknown option: --xtensa-cpu=esp32`** |
| `--esp-profile=bare` | accepted (then correctly complains the *target* is not ESP) |
| `--esp-profile=idf` | **`unknown option: --esp-profile=idf`** |
| `--nonsense-flag` | `unknown option: --nonsense-flag` — the genuine case |

The last row is the problem: **a real diagnostic and a wrong one are the same
sentence.** `--esp-profile` shows the right behaviour exists — it validates its
value and says something specific — so this is an inconsistency between option
handlers, not a missing capability.

## Why it costs more than a wording nit

- **It aims the reader at the wrong half of the argument.** `unknown option`
  means "this flag does not exist", so the reader checks spelling, greps docs,
  and concludes the documentation is stale — when the flag is right and the value
  is wrong. `--target=` is the flag a new cross-compiling user types first.
- **It makes the CLI unprobeable.** Anything enumerating accepted options by
  running them — a doc check, a completion script, an agent auditing `--help`
  against reality — cannot distinguish a nonexistent option from a live one given
  a placeholder. This is not hypothetical: it produced a **false finding in the
  sweep that found it**. `--xtensa-cpu=lx6` is documented correctly at
  `docs/reference/cli.md:122`, was probed as `--xtensa-cpu=esp32`, answered
  `unknown option`, and was one step from being filed as a documentation bug.
  The wrong answer was *plausible*, which is this repo's expensive class.
- It interacts with [[bug-a-help-does-not-advertise-flags-the-compiler-accepts]]:
  when `--help` omits a flag AND a bad value calls it nonexistent, both available
  instruments agree on a false answer.

## Suggested shape

Split the two verdicts at the parse site: an option matched by name with an
unacceptable value should say so and, where the set is closed and small, name the
accepted values — `--esp-profile` already does the first half. Reserve
`unknown option` for a name that matches no handler.

Worth a decision rather than a guess: whether the value list is printed for every
closed-set option or only where it is short. `--target` has
`--list-targets` already, so pointing at it beats printing the list.

## Gate

`make compiler/pascal26` plus the six rows above, run. Do not widen — a suite is
not what checks a diagnostic's text. Note also
[[chore-t-a-wikilink-to-a-ticket-that-does-not-exist-is-never-detected]]'s
neighbour, face 231: `unknown option:` wording is asserted by
`grep -q` in the Makefile at least once, so **grep for the current wording before
changing it**.
