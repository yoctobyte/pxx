---
slug: bug-p-read-write-exit-and-halt-cannot-be-declared-as-user-routines
title: "`read`, `write`, `readln`, `exit`, `halt` cannot be DECLARED as user routines"
track: P
prio: 40
type: bug
status: backlog
owner: ""
blocked-by: []
summary: "MEASURED 2026-09-06 at d4fe6ede3, compiler e7d85ae887d9. `function read(x: LongInt): Boolean;` is refused at the DECLARATION with `expected name` -- the name never reaches the symbol table, at top level and nested alike (`nested routine: expected name`). fpc 3.2.2 -Mobjfpc compiles the same program and runs it. THE SET IS EXACTLY FIVE AND WAS ENUMERATED, NOT GUESSED: probing 18 builtin names, pxx refuses `read`, `write`, `readln`, `exit`, `halt` where FPC accepts, and refuses `writeln` where FPC ALSO refuses -- so that sixth row is PARITY and must not be `fixed`. Every other name tried is already fine in both: `str val new dispose length pos copy insert delete abs ord chr inc dec`. So this is not 'builtins are reserved' in general; it is these five, which are the ones the STATEMENT parser has special syntax for. FOUND BY ATTEMPTING THE TARGET: it is the wall uPSRuntime stops on at line 2377, `function read(var Data; Len: Cardinal): Boolean;` -- a nested helper the unit calls as `if not read(HDR, SizeOf(HDR))`, which is ordinary Object Pascal. THIS ALSO RETIRES A STALE CLAIM: [[feature-embed-pascal-script]] recorded uPSRuntime as stopping on a `{$IF}` comparison; with `--mimic-fpc` it now parses to line 3049 and the `{$IF}` wall is gone, exactly as the DWScript work predicted. NOT A ONE-LINER: `read`/`write` are lexed as keywords because `write(a, b:2:3)` needs special argument syntax, so the fix is to make them CONTEXT-SENSITIVE (a user declaration shadows the builtin) rather than to un-reserve them, and it touches statement parsing -- which is why this is filed rather than fixed in passing."
---

# `read`, `write`, `readln`, `exit`, `halt` cannot be declared as user routines

- **Type:** bug (Pascal frontend — these names are reserved where FPC's are not)
- **Track:** P — the lexer/declaration path
- **Found:** 2026-09-06, attempting [[feature-embed-pascal-script]]

## Repro

```pascal
program sh;
function read(x: LongInt): Boolean;
begin read := x > 0; end;
begin if read(1) then writeln('ok'); end.
```

`fpc 3.2.2 -Mobjfpc` prints `ok`. pxx: `pascal26:2: error: expected name`.

Nested is the same shape and the same defect:
`pascal26:3: error: nested routine: expected name`.

## The set, enumerated over 18 builtin names

| name | pxx | fpc |
| --- | --- | --- |
| `read` `write` `readln` `exit` `halt` | **refused** | accepted |
| `writeln` | refused | **also refused** — this row is PARITY |
| `str` `val` `new` `dispose` `length` `pos` `copy` `insert` `delete` `abs` `ord` `chr` `inc` `dec` | accepted | accepted |

**The `writeln` row is the control.** It is the reason this ticket does not say
"builtins are reserved and should not be": one of the six is a divergence-free
row, so a fix that simply un-reserves the lot would break parity rather than
restore it.

## Why it is not a one-line fix

`read` and `write` are lexed as keywords because the statement forms need
syntax no ordinary call has — `write(x:8:2)`, the file-handle first argument.
The fix is to make them **context-sensitive**: a user declaration of the name
shadows the builtin for that scope, which is what FPC does. That is a change to
declaration parsing and name resolution, not to a reserved-word list, and it
wants its own gate — hence filed rather than fixed in passing.

## Done when

The repro compiles and prints `ok`, `write(x:8:2)` still formats, `exit` with no
user declaration still exits, and `function writeln(...)` is still refused.
