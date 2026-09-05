---
slug: bug-p-sysopen-intrinsic-shadows-a-user-function-name
title: "A Pascal program that defines `function sysopen(...)` fails with `expected name`"
track: P
prio: 15
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-08-27
summary: "sysopen/syswrite/sysclose/sysfchmod are compiler INTRINSICS with dedicated tokens (tkSysOpen &c), so the lexer never produces an identifier for them and a user program cannot declare a function with one of those names. The diagnostic is `expected name`, which does not mention the reservation. Real but nearly unreachable: prio 15."
---

# Repro

```pascal
program T;
function sysopen(const p: AnsiString; f: Integer): Integer;
begin sysopen := 0; end;
begin writeln(sysopen('x', 1)); end.
```

```
pascal26:2: error: expected name
  near: program T  function >>> sysopen  const
```

# Why it happens

`sysopen` / `syswrite` / `sysclose` / `sysfchmod` are compiler **intrinsics**
with their own token kinds (`defs.inc:4510` — *"sysopen/sysread/sysclose are
compiler INTRINSICS (tkSysOpen &c)"*). The lexer emits `tkSysOpen` rather than
an identifier, so the declaration parser sees a token where a name belongs and
says so, accurately but unhelpfully.

# Which row of the compat table this is

Row 3, *FPC accepts a form we reject*, ranked by how much real code uses it —
which is nearly none. It is **not** the "diagnostic differs" row: the program
does not compile at all, so a program whose behaviour changes can be named,
which is the line separating a low-prio ticket from a `rejected/` one.

# Suggested fix

Probably not un-reserving the names — they are deliberate intrinsics. A
diagnostic naming the reservation would be enough:

```
error: 'sysopen' is a compiler intrinsic and cannot be redeclared
```

# Provenance

Found while building the wasm Phase 1 self-test, which needed file output from a
standalone program and first tried to declare these three as shims. The actual
resolution was better — the intrinsics are callable from a standalone program
*without* declaring them, which is what let the self-test exercise
`compiler/wasmenc.inc` without including it into `compiler.pas`.

## 2026-09-05 (frankB) — this is the CALL side of a DECLARATION defect

Measured: the call never happens. `procedure Write;` / `procedure SysOpen;` is
refused at the DECLARATION with `expected name`, so the user name cannot exist
to be shadowed, and the call-site framing above is downstream of that.

Root cause and the whole cluster — nine spellings, one mechanism, with the
blast radius enumerated — is
[[bug-p-nine-intrinsic-spellings-are-hard-keywords-so-they-cannot-be-user-names]].
**Work that one, not this one**: a fix aimed at the call site is aimed at the
wrong half, and fixing only the declaration would leave a routine that is
declared and then silently never called, which is worse than today's refusal.

## Log
- 2026-09-05 — resolved by `5f177b181` (the fix; closed in `6f8d72fb1`). Fixed: sysopen/sysread/syswrite/sysclose/sysfchmod are soft keywords, declarable as any kind of name, intrinsics unchanged when unshadowed, System.X escape hatch. test/test_soft_keyword_sysargs.pas (20 rows), positive-controlled against pin v404. See bug-p-nine-intrinsic-spellings-are-hard-keywords-so-they-cannot-be-user-names for the whole conversion and three corrections to its blast-radius section..
