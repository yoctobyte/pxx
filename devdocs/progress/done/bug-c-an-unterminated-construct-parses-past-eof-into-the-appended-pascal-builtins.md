---
slug: bug-c-an-unterminated-construct-parses-past-eof-into-the-appended-pascal-builtins
track: C
prio: 45
type: bug
blocked-by: []
summary: "A C source with an unterminated construct parks TokPos on the first token of the appended Pascal builtin units, so the diagnostic reports `in: ./compiler/builtin/builtinheap.pas` and a `near:` window of Pascal source. The C parser does not stop at the end of its own token stream."
status: done
owner: frankC
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

## Resolved for STATEMENTS; the declaration half is split out. frankC, 2026-08-30

| shape | before (`pinned` 53800fbeb0b6) | after |
| --- | --- | --- |
| `int main(void) { return 1;` | `pascal26:2: expected C expression` + `in: builtinheap.pas` | `pascal26:1: unterminated C construct` |
| unterminated nested block | same | `pascal26:6: ...` |
| unterminated after a crtl pull | same | `pascal26:2: ...` |
| unterminated `struct` / `enum` / initializer | `main function not found` at platform_backend.pas:1313 | **unchanged** → [[bug-c-an-unterminated-declaration-still-parses-the-appended-pascal-rtl]] |

### Not a printer fix

The old diagnostic was **correct in every part** — token 9 really is
`builtinheap.pas`'s first token, and line 2 really is its line. Nothing about the
message was wrong; the parser had no business being there. Fixing the message
would have made a correct mechanism print a plausible lie.

### One predicate, and it is not a token index

`CTokIsPastCSource` asks the **Pascal source range**, not `TokPos >= userTokEnd`.
That is what makes it right in the case that would break an index test:
`CLexAppend` plants `PasMarkTokFile(unitStart, '')` over every appended **C**
region, so the pulled crtl modules answer `''` and are still walked, while an
appended Pascal unit carries its real path. An index would have refused the crtl
pull, which is the mechanism the whole design exists to serve. The table is
populated in every build, not only under `-g`.

### The refactor, and why it is one and not fourteen

Fourteen loops were written as `while (CurTok.Kind <> tkEnd) and (CurTok.Kind <>
tkEOF) do`, and all fourteen shared the same hole — `tkEOF` is a test that
**cannot fire**, because the C stream's EOF is deleted when units are appended.
They now read `while CBlockContinues do`, one definition, which refuses at the
boundary. Fourteen copies of a condition is fourteen chances to fix one of them.

Two call shapes reach one refusal (`CRefuseUnterminated`): the loop condition,
and `ParseCStatementAST`'s entry for a statement not inside such a loop
(`if (x) <stmt>` running off the end). The entry check must **error**, not
return -1 — returning without consuming would spin those loops forever, since
the kind is not `tkEOF`.

`ErrorAt`, not `Error`: the line is the user's last C line and the `in:` /
`near:` context is suppressed, because from there both would describe Pascal.

### The root cause is banked, not fixed

**The C parser has no end.** Deleting the C `tkEOF` is deliberate and makes the
crtl pull work; the price is that every `tkEOF` test in the C parser is inert and
each loop family grows its own substitute. Giving the parser a real terminator
would delete both guards and make `tkEOF` mean what it says in all thirty loops.
Costed in the split-out ticket rather than bolted on as a third guard.

### A dialect note found the hard way, twice

**pxx NESTS `{ }` comments.** A `{` inside a comment — `... an unterminated
`struct S { int a;` consumed ...` — swallows the terminating `}` and reports
`unexpected character` a hundred lines later, at the first token that stops
parsing as prose. Two builds lost to it. Not filed: the file compiles under both
pxx and the FPC seed once the brace is gone, so nothing is broken; it is a
writing hazard for anyone quoting C in a Pascal comment.

### Tests

`cunterm` and `cunterm_pull` in `test-core`, **both real before/afters** — the
pinned compiler gives `pascal26:2: expected C expression` and the builtin path
for each. The second exists because the boundary must not be "anything was
appended": its crtl region is appended C and must still be walked. Four C corpus
programs (bitfield, Duff's-device switch, char promotion, `__has_include`) still
compile. Self-host: converged, 1 round, `3e437e986be5`.

## Log
- 2026-08-30 — resolved, commit 43cc17106.
