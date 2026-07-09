---
prio: 55
---

# C preprocessor: macro-arg paren/comma scan ignores string & char literals

- **Type:** bug (C frontend / preprocessor) — **Track C** (`compiler/cpreproc.inc`).
- **Status:** done
  bring-up (blocker wall #2, right behind the `__STDC_VERSION__` predefine).
- **Blocks:** [[feature-c-corpus-duktape]].

## Symptom
After the C99 predefine unblocked wall #1, duktape hit:

```
Expected: ), but got:  (   near: thr "Symbol("
pascal26: error: unexpected token ()
```

at `duk_push_literal(thr, "Symbol(")` (duktape.c:25596), where `duk_push_literal`
is a function-like macro:

```c
#define duk_push_literal(ctx,cstring)  duk_push_literal_raw((ctx),(cstring),sizeof((cstring))-1U)
```

## Root cause
`CPExpandRange` (compiler/cpreproc.inc, the function-like-macro argument collector,
~line 1140) scanned for `(` / `)` / `,` to split arguments **without skipping string
or character literals**. A `(`, `)`, or `,` inside a string argument (e.g. the `(` in
`"Symbol("`) was counted as real punctuation → argument boundaries and paren depth
went wrong → the expansion was garbage and the parser choked.

## Minimal repro
```c
#define PICK2(a, b) (b)
extern int push_raw(int, const char *, unsigned long);
int main(void){ return push_raw(0, PICK2(0, "Sym(bol,)") != 0); }
```
gcc `-E` expands cleanly; pxx (pre-fix) mis-split the args and emitted stray tokens.

## Fix (applied)
In the arg-collection loop, when the scan hits `"` or `'`, skip to the matching
closing quote (honouring `\` escapes) before testing for parens/commas. See
`compiler/cpreproc.inc` (the `if (src[q] = '"') or (src[q] = '''')` branch).
Regression: `test/cpreproc_macro_arg_string_paren_b227.c` (exit 42), wired into
`test-core`.

## Follow-up (not blocking)
The same string-blind scan pattern also appears in the `#if`-expression macro-arg loop
(~line 497) and the balanced-group scanners `CPMatchParen` / `CPBalancedGroupEnd`
(~line 1017). They did not fire on duktape, but a string literal with unbalanced
parens routed through `#if` or the C99 rescan path would hit the same bug. Harden them
the same way when convenient (low priority — no known failing input yet).

[[bug-c-preproc-missing-stdc-version-predefine]] · [[feature-c-corpus-duktape]]

## Log
- 2026-07-09 — resolved, commit c50065e8.
