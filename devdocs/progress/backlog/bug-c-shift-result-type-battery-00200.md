---
prio: 45
---

# C shift-result-type battery (00200): result type = promoted LEFT operand across all int classes

- **Type:** bug (C type model — integer promotion + shift result type +
  sizeof-of-expression + unary-minus signedness). Track C.
- **Split 2026-07-08** out of [[bug-c-expr-result-type-model]] (00178 + 00104
  done; this is the remaining deep sub-effort).

## Failing test
- 00200 (Vincent Lefevre's lshift-type.c): ISO C99 6.5.7p3 — for `X << T`, the
  integer promotions run on each operand and the RESULT TYPE is that of the
  promoted LEFT operand. The battery probes sign+size of the result across
  short/int/long/long long x signed/unsigned via
  `PTYPE(M) = (sign of M via -(M)<0) * sizeof((M)+0)`. 30 cases fail.

## Root cause
pxx mis-types shift results (e.g. `(short)1 << (short)1` should be signed int —
short promotes to int — but pxx types/treats it such that `-(result) < 0` is
false, i.e. unsigned). Needs: correct integer promotion (short/char -> int),
shift result = promoted-left type (NOT the usual-arithmetic-conversions common
type), sizeof-of-expression honoring that type, and signed unary minus keeping
signedness. Interacts with the constant-type ladder just landed for 00104.

## Gate
00200 exit 0 (30/30); drop from pxx.skip; c-conformance + corpus green;
self-host byte-identical.
