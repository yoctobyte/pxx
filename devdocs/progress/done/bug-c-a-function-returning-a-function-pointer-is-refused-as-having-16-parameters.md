---
slug: bug-c-a-function-returning-a-function-pointer-is-refused-as-having-16-parameters
track: C
type: bug
prio: 80
status: done
found: 2026-09-02
found-by: frankZ
owner: frankD
blocked-by: []
summary: "`void (*look(int a))(void) { }` was refused with `more than 16 parameters not supported (MAX_PROC_PARAMS)`. An UNINITIALISED READ, not a parse collision: ParseCSubroutine checks `paramsOverflow` after the fnRetIsFunc branch and only the OTHER arm ever assigned it, so a function returning a function pointer read the flag off the stack. The ZERO-parameter form kept working throughout, which is why nothing caught it earlier and why the new test labels that row. Latent since the fnRetIsFunc arm existed; surfaced by d71642873, which changed what sat in that stack slot without touching the variable. FIXED 2026-09-02."
---

# A function returning a function pointer, refused for having 16 parameters

Reported by frankZ against master with a three-line repro:

```c
void t(void){}
void (*look(int a, int b))(void){ (void)a; (void)b; return t; }
int main(void){ return look(1,2)==t ? 42 : 1; }
```

```
pascal26:2: error: C function definition: more than 16 parameters not supported (MAX_PROC_PARAMS)
```

The real casualty was `test/cfn_return_fnptr_b105.c`, whose own header says it
exists for `sqlite3OsDlSym`.

## The boundary — and the row that never failed

| shape | before |
| --- | --- |
| `void (*p)(void) = t;` — fn-pointer VARIABLE | ok |
| `int apply(int cb(int), int x)` — function-TYPED parameter | ok |
| `void (*look(void))(void) { }` — **zero** parameters | **ok** |
| `void (*look(int a))(void) { }` | REFUSED |
| `void (*look(int a, int b))(void) { }` | REFUSED |
| the same with a forward declaration as well | REFUSED |

The first four rows are frankZ's probes; the zero-parameter row is the one this
ticket exists to record. **The family had a working member the whole time**, so
any test written around that member stayed green through the outage.

## Cause

`ParseCSubroutine` declares `paramsOverflow` and checks it near the bottom,
after both arms of `if fnRetIsFunc`. It was assigned in the `not fnRetIsFunc`
arm only — the one that parses a parameter list. A declaration whose declarator
already carried its parameters (`RET (*name(params))(args)`) takes the other
arm, parses no list, and left the variable untouched; the check then read
whatever the stack held.

**Proved by exhaustion over the source, not by instrumentation.** The single
`paramsOverflow := True` sits inside the parameter loop that this path does not
enter, so a True at the check could not have come from an assignment at all.
That also explains the zero-parameter row, which a parse-desync theory does not:
a desync would break that shape too, while a stack slot that happens to hold
zero produces exactly the observed split.

The three siblings the branch sets in BOTH arms — `name`, `nparams`,
`isVariadic` — are why this was the only variable reachable in that state.

## Why now

Latent for as long as the fnRetIsFunc arm has existed. `d71642873` (busybox
rung 3) added an arm to the parameter loop for function-TYPED parameters, which
changed what sat in that stack slot. **A change that cannot touch a variable and
still moves the answer is the tell for an uninitialised read** — worth more than
the error text, which named a parameter count for a function with one parameter.

frankZ's own reading, offered as a hypothesis and not a measurement, was that
`CParseFnSigGroup` was being entered at declarator level and eating the inner
list. It is not entered there — it is not entered at all on this path. The
attribution half of that report was right and useful: the auto-filed range
(last-good `49d0ac95f76d`, bad `65b719ab48ae`) points at `18b3ec2a6`, and it is
not that; `49d0ac95f76d` is a tstate commit off seven's line, so the linear
range lies here. Do not bisect toward `18b3ec2a6`.

## Fix

`paramsOverflow := False` moved above the branch, with the reasoning at the
site. The duplicate initialiser in the parameter-list arm is removed rather than
left as a second statement of the same fact.

## Test

`test/c_fn_returning_fnptr_params.c`, 6 rows diffed against gcc, wired into
`test-core` beside `cfn_return_fnptr_b105`. Row 1 is the zero-parameter shape,
labelled — it is the control that this family had a member which cannot detect
the defect. Rows 5 and 6 call THROUGH the returned pointer with arguments, so a
fix that recovered only the outer parameter count fails there instead of
passing.

`--tier quick` does not reach `cfn_return_fnptr_b105`; Track T's fuller tier is
what found this, which is the sampling model working as designed.

## Log
- 2026-09-02 — resolved.
