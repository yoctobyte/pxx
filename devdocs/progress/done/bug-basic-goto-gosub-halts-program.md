---
prio: 70  # auto
---

# bug: BASIC frontend's GOTO/GOSUB silently halt the program instead of jumping

- **Type:** bug (Track A — `compiler/blexer.inc`/`bparser.inc`)
- **Status:** done (2026-07-06)
- **Owner:** track-z-agent
- **Opened:** 2026-07-05 (found while exploring the existing, untracked BASIC
  frontend for [[feature-pxx-basic]])

## What's broken

`compiler/blexer.inc` lexes `GOTO` and `GOSUB` straight to `tkHalt` (the
`Halt`-statement token):

```pascal
if lower = 'goto' then Result := tkHalt;   { line 37 }
...
if lower = 'gosub' then Result := tkHalt;  { line 46 }
...
if lower = 'return' then Result := tkExit; { line 49 — RETURN -> function exit,
                                              not a GOSUB return-address pop }
```

Every BASIC program containing a `GOTO`/`GOSUB` anywhere **halts the whole
program the instant it reaches that statement** — no jump, no error, clean
exit code 0. Confirmed minimal repro:

```basic
10 PRINT "A"
20 GOTO 40
30 PRINT "SKIPPED"
40 PRINT "B"
```

Output: `A` only. Line 40 (`B`) never prints — `GOTO 40` doesn't jump forward,
it just ends the program. Same result for a backward `GOTO` (a `WHILE`-style
loop written with line numbers never loops — one pass, then exits clean).

This also silently breaks `test/test_basic_comprehensive.bas`, the frontend's
own existing test file, which relies on `GOTO`/`GOSUB` for its first section
(classic jump-style control flow) — it currently prints one line of ~15+
expected and exits 0, looking "successful" unless you check the output.

## Why urgent, not just a bug

Silent-wrong is worse than a compile error here: the program *builds cleanly*,
*runs*, *exits 0* — nothing signals anything is wrong unless you read the
output. Matches this project's own "correctness-sensitive, not a compile-error
risk" bar used elsewhere (e.g. Rust drop/move-tracking).

## Likely fix shape (not investigated further — Track A to size properly)

- `GOTO`/`GOSUB` need their own real token(s), not aliases to `tkHalt`.
- Lowering needs actual jump-to-line-number semantics: `GOTO` = unconditional
  jump to the statement at that line number; `GOSUB` = push a return point and
  jump; `RETURN` = pop that return point and jump back (NOT `tkExit`/function
  return — currently conflated).
- Line numbers need to already exist as jump targets somewhere in
  `bparser.inc`/the BASIC->IR lowering (labels? a dispatch table?) — check
  what's there today before assuming this needs new IR support; this may
  already be a "just wire GOTO/GOSUB to the existing label mechanism" fix
  rather than new machinery. Not confirmed — first thing to check when picked
  up.

## Log
- 2026-07-05 — found and filed while investigating the existing (untracked)
  BASIC frontend in response to a "PXX Basic as a wild demo" discussion. Not
  fixed — Track B (this session) doesn't touch `compiler/**`; handing off.
  See also [[feature-pxx-basic]] for the broader "make this a real, finished,
  fun demo dialect" idea this bug blocks.

## Fixed (2026-07-06, combined-track session — Track A files, user-confirmed multi-track ok)

- **blexer.inc:** `goto`/`gosub` no longer alias `tkHalt` — they stay `tkIdent`
  and bparser dispatches on text (BASIC is case-blind).
- **bparser.inc:** rides the SHARED `AN_LABEL`/`AN_GOTO` + `GotoLabel*`
  machinery the C frontend already uses — no new AST/IR:
  - prescan over the main-program tokens registers "L<line>" per distinct
    GOTO/GOSUB target and "G<k>" per gosub site;
  - ParseBBlock emits `AN_LABEL` when a line number is a registered target
    (others skipped as before); duplicate target line numbers = compile error;
  - `GOSUB`/`RETURN` use a shift-register return stack in one Int64
    (`__gosub_ret`, 6 bits per site id, max 63 gosub sites, depth 10):
    GOSUB = overflow-guard + push + goto + return-label; RETURN = pop +
    if/else dispatch chain over the G<k> labels. Both failure modes are
    RUNTIME-CHECKED and loud: nesting >10 or RETURN-without-GOSUB prints
    `RUNTIME ERROR: ...` and halts 1 — never silently wrong.
  - labels are re-registered after the parse, right before CompileAST,
    because a `USES unit` compiles the unit through the Pascal parser which
    resets GotoLabelCount (found via test_basic_comprehensive.bas).
- **Drive-by:** LET-less first assignment (`I = 0`) was broken by a
  pre-existing off-by-one (`Tokens[TokPos+1]` vs `Tokens[TokPos]` for the
  `=` check — verified broken on the pinned stable too). Fixed.
- **RETURN inside a proc** still lowers to plain `AN_EXIT` (CurProc check),
  main-line RETURN is the gosub return.

Verified: ticket repro prints A,B; backward-GOTO loop terminates; nested
GOSUB (main→sub1→sub2, then main→sub2) returns correctly; 9-deep GOSUB
recursion ok, 15-deep trips the guard; stray RETURN errors exit 1;
test_basic_comprehensive.bas now runs its full ~21-line output (was 1 line +
exit 0). New regression test test/test_basic_goto_gosub.bas + the
comprehensive file wired into make test. Full suite + self-host fixedpoint
byte-identical (build rule cmp).
