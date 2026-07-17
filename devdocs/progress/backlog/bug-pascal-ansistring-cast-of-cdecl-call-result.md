---
summary: "SILENT: AnsiString(<direct external-call PChar result>) yields a garbage length (over-read/crash); via a variable it is correct"
type: bug
prio: 55
---

# `AnsiString(func())` of an external cdecl PChar result mis-lowers — garbage length (SILENT)

- **Type:** bug (Track A — typecast lowering, shared `parser.inc`/`ir.inc`; the
  Pascal-frontend semantics is P, the codegen is core A). **SILENT** — no error, a
  garbage-length managed string that over-reads the heap and prints garbage / crashes.
- **Status:** backlog
- **Found:** 2026-07-17, building the thin `lib/pcl/tk.pas` Tcl/Tk embed — a hello
  window worked, but `AnsiString(Tcl_GetStringResult(interp))` dumped 72 KB of Tcl heap.
- **Owner:** —

## Minimal repro

```pascal
program pcast;
function getenv(name: PAnsiChar): PAnsiChar; cdecl; external 'libc.so.6';
var p: PAnsiChar; s: AnsiString;
begin
  p := getenv('PATH');
  s := AnsiString(p);                 { via a variable  -> len 331  CORRECT }
  writeln('via-var len=', Length(s));
  s := AnsiString(getenv('PATH'));    { direct call cast -> len 4415872074128570672  WRONG }
  writeln('direct  len=', Length(s));
end.
```

Output:
```
via-var len=331
direct  len=4415872074128570672
```

## Characterisation (narrowed)

- Casting a **direct function-call expression** whose type is `PAnsiChar`/`PChar` to
  `AnsiString` picks the wrong conversion path: it treats the returned pointer as an
  **already-managed AnsiString** (reads a length/refcount header at `ptr-8`) instead of
  doing the `PChar → AnsiString` **strlen-copy**.
- **Routing through a `PAnsiChar` variable first fixes it** (`p := f(); s := AnsiString(p)`
  → correct). So the defect is specific to the *call-expression* operand's inferred cast
  path, not the pointer/ABI (StrPas on the same pointer is correct).
- A cast of a **local** Pascal function's PChar result did NOT reproduce in a quick check
  — the external **cdecl** call is the trigger seen; confirm whether ordinary-call PChar
  results are affected too (the type-of-the-call-node is the suspect, cdecl may be
  incidental).

## Why it matters

This is the textbook silent class this project hunts: no diagnostic, a plausible-looking
value, memory over-read. It bites **every** idiomatic C-interop line of the form
`s := AnsiString(SomeCFunc(...))` — extremely common when wrapping a C library
(`getenv`, `strerror`, `Tcl_GetStringResult`, any `char*`-returning API). The
[[project_oop_corpus_ladder_findings]] rule — every serious bug here is silent — applies.

## Workaround (in use)

`StrPas(PChar(func()))` (lib/rtl `strings`/`sysutils`) copies to the NUL correctly and is
the RTL idiom regardless. `lib/pcl/tk.pas` uses it.

## Fix direction

In the `AnsiString(...)` typecast lowering, when the operand's static type is
`PChar`/`PAnsiChar` (call-expression or not), always take the pchar→ansistring
strlen-copy path — never the managed-string-header reinterpretation. Likely a
type-classification miss on the call node (cf. the b346 "IR value node is a subtree"
family, [[project_case_selector_reeval_and_fuzzer_narrowness]]).

## Acceptance

- Both forms above report `len=331`.
- A `test/test_*.pas` regression: `AnsiString(<cdecl PChar func>())` has the correct
  length and content.
- Gate: `make test` + self-host byte-identical.
