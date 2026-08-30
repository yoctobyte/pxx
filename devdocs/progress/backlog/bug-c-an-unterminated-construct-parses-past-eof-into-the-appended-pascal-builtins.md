---
slug: bug-c-an-unterminated-construct-parses-past-eof-into-the-appended-pascal-builtins
track: C
prio: 45
type: bug
blocked-by: []
summary: "A C source with an unterminated construct parks TokPos on the first token of the appended Pascal builtin units, so the diagnostic reports `in: ./compiler/builtin/builtinheap.pas` and a `near:` window of Pascal source. The C parser does not stop at the end of its own token stream."
status: backlog
---

# An unterminated C construct parses into the Pascal builtins

```c
int main(void) { return 1;      /* no closing brace */
```

```
pascal26:2: error: expected C expression
  in: ./compiler/builtin/builtinheap.pas
  near:       >>> unit builtinheap
```

The `near:` window shows `unit builtinheap` — Pascal source, in a C compile.

## Measured

`PXXDBG=a.srcmap:*` on that program:

```
PXXDBG a.srcmap PLANT start=9 tokcount=9 lexing=TRUE ./compiler/builtin/builtinheap.pas
PXXDBG a.srcmap tok=9 srcline=2 lexing=FALSE tokcount=33283 -> ./compiler/builtin/builtinheap.pas
```

The C source is exactly nine tokens (`int main ( void ) { return 1 ;`), indices
0..8. The Pascal builtin and RTL units are appended from index 9 on. The
unterminated body leaves `TokPos` at 9, so the diagnostic asks about a token
that genuinely belongs to `builtinheap.pas` — the path is *correct for the token
index*, and the token index is the bug.

Not a diagnostic bug, and not the C `in:` fallback
(`feature-c-diagnostics-name-the-module-they-are-in`): the Pascal range table
answers here, so the C arm never runs. The same off-by-nothing would hand those
Pascal tokens to the C **parser** if it kept going, which is the part worth
worrying about — a wrong error message is the visible half.

## What to fix

The C parser should treat the end of its own token range as EOF and say so
(`unexpected end of file in <construct>` with the line of the construct's
opening), rather than reading whatever the shared token array holds next.
Whether the C token stream even needs a recorded end, or whether the builtins
should be lexed before the C source rather than after, is the design half.

## Gate

The example reports an unterminated-construct error naming the `.c` and its own
line, with no `in:` line and no Pascal text in the `near:` window. The three
`test_incdiag_*` rows and `cdiag_module` / `cdiag_main` stay green. Self-host
byte-identical.
