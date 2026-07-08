---
prio: 30
---

# C: a crtl auto-pulled int function used inline in a signed compare reads unsigned

- **Type:** bug (C frontend — return-type threading at the call site for
  hand-declared / auto-pulled crtl prototypes). Track C.
- **Found:** 2026-07-08 wiring the crtl net-header smoke
  (bug-c-crtl-missing-net-headers-enet).

## Symptom
```c
struct addrinfo *ai = 0;
if (getaddrinfo("h","80",0,&ai) >= 0) return 5;   /* WRONG: taken (getaddrinfo returns -2) */
int rc = getaddrinfo("h","80",0,&ai);
if (rc >= 0) return 5;                              /* correct: not taken */
```
Inline, the -2 return compares as if UNSIGNED (>= 0 true); stored into an
`int` first, it's correctly signed. A plain local `int neg(void){return -2;}`
does NOT reproduce (`neg() >= 0` is correctly false), so it is specific to the
crtl auto-pulled / hand-declared prototype path (feature-c-crtl-bind-hand-
declared-prototypes) not threading the declared `int` return type onto the
call node when the result feeds directly into a comparison.

## Direction
Check how a call to a crtl-pulled proc gets its result type (AN_CALL ASTTk =
Procs[sig].RetType) and whether the pulled/rebound prototype leaves RetType
unsigned or tyUnknown so the comparison lowers unsigned. Compare against a
normally-declared function (which works).

## Gate
`getaddrinfo(...) >= 0` inline evaluates signed; a focused repro; c-conformance
+ corpus green.

## Log
- 2026-07-08 — resolved, commit f94264b6.
