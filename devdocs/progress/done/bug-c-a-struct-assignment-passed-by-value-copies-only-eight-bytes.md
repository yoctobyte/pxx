---
track: C
prio: 60
type: bug
blocked-by: []
summary: "`f((*p) = s)` — a struct assignment used as a value and handed to a BY-VALUE parameter — passed only the first eightbyte; the rest was stack garbage. ResolveNodeRec had no AN_ASSIGN arm, so the argument resolved to REC_NONE and the C by-value temp was sized by the 8-byte fallback instead of the struct's size. csmith seed 91110."
status: done
---

# A struct assignment passed by value copies only eight bytes

Found 2026-08-16 reducing csmith seed 91110, the finding
[[feature-c-csmith-differential-fuzzing]] left unreduced at the end of the
previous session.

## Reduced repro

```c
struct S1 { int f0; long long f1; };
static struct S1 g = {1, 2};
static void take(struct S1 p) { printf("f0=%d f1=%lld\n", p.f0, p.f1); }
int main(void) {
  struct S1 l = {0x6F1F9E91, 0xAD9135A7A9E0DFB1LL};
  struct S1 *pg = &g;
  take(((*pg) = l));
}
```

| | f0 | f1 |
| --- | --- | --- |
| gcc | 1864343185 | -5939907439299076175 |
| pxx | 1864343185 | **4431544** |

The STORE to `g` was correct in both. Only the value handed to the callee was
short.

## Root cause

`ResolveNodeRec` answers "which record is this node's". It had arms for IDENT,
FIELD, INDEX, CALL, comma, casts, compound literals — and none for AN_ASSIGN,
so a struct assignment used as a value came back REC_NONE. The C by-value
argument path (`needTemp` in ir.inc) then sized its copy with
`RecSize(REC_NONE)`, which is the 8-byte fallback:

```
20: copy_rec a=18 b=19 ival=16      <- the assignment itself: right
22: copy_rec a=17 b=21 ival=8       <- the argument temp: half the struct
```

So the first eightbyte was copied and the second was whatever the temp's stack
slot held.

The fix is the arm, not the size computation: an assignment yields the value
STORED, so its record is the DESTINATION's — literally the same sentence the
comma arm two lines above already states for its right operand, and the type
half of the aggregate rule the AN_ASSIGN lowering in `ir.inc` states for its
value. `Result := ResolveNodeRec(ASTLeft[node])`.

## Why the corpora missed it

Same reason as its sibling
[[bug-c-a-struct-assignment-used-as-a-value-runs-its-rhs-twice]] (csmith seed
90202, previous session): a person writes `*p = s; f(*p);`. The chained form is
legal C that hand-written code has no reason to produce, and the failure is a
plausible wrong value in the SECOND half of a struct, not a crash — every value
derived from the first field stayed right. lua, sqlite, tcc, zlib and the
c-testsuite all pass with the bug present.

## Gate

`make compiler/pascal26` (self-host fixedpoint, byte-identical) + `tools/gate.sh
quick` GREEN. Seed 91110's full 1723-line program now agrees with gcc on every
checksum. Pinned by `test/cstruct_assign_value_byvalue_arg.c` in `make test`:
deref destination, named destination, a 24-byte struct too large for any
register pair, and two such arguments in one call.

## Log
- 2026-08-16 — resolved, commit PENDING-COMMIT.
