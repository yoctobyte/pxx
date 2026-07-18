---
summary: "C struct with a field at byte offset > 65535 miscompiles the field access (wrong value); suspect a 16-bit offset wrap"
type: bug
prio: 30
---

# Huge C struct: a field past 64 KB offset reads/writes the wrong slot

- **Type:** bug (Track C — C struct field-offset lowering). Silent wrong value, not a
  crash. **Pre-existing** (reproduces on binaries well before the dynamic-array work;
  found 2026-07-18 while stress-testing the UField dynamic conversion with big structs).

## Repro

```c
struct s { int f0; int f1; /* ... */ int f16999; };   /* 17000 int fields */
int main(void){ struct s b; b.f0 = 7; b.f16999 = 35; return b.f0 + b.f16999; }
```

- **Expected:** 42 (7 + 35).
- **pxx:** exit 70 (= 35 + 35) — `b.f0` reads f16999's value, i.e. the two accesses
  alias. f16999 is at byte offset 67996 (> 65535).

## ROOT CAUSE (2026-07-18) — NOT a 16-bit offset wrap

Original "16-bit offset wrap / >64 KB" suspicion was WRONG. Real cause: the C struct-body
parser (`CParseStructBody` in `cparser.inc`) buffers a struct's fields in fixed local
arrays `bf*` sized `const MAX_BF = 256`, and every buffer site was guarded `if bfCount <
MAX_BF then ...`. A struct with **> 256 fields SILENTLY DROPS every field past #256** —
they are never handed to `AddUField`, so `FindUField` can't find them and
`RecFieldOffset` returns its default **0**, aliasing them onto field 0. The running byte
offset (and hence struct SIZE / frame layout) is computed separately and stays correct,
which is why the size looked fine and only *named* access broke.

Corrected facts: the trigger is **field COUNT > 256, not offset > 64 KB** (a 3-field
struct with a field at byte offset 70004 is fine; a 300-`int` struct — 1200 bytes — aliases
`f256`..). Exactly index 256 is the cliff. **C-only** — Pascal records add fields directly
per field (no `bf*` buffer) and a 400-field Pascal record was verified correct.

## Fix (DONE)

Made the `bf*` buffers **local dynamic arrays** (`array of`, recursion-safe for nested/anon
structs — a global buffer would be clobbered by the recursive sub-struct parse) pre-sized
per struct to a field-count upper bound (`endIdx - startIdx + 2`: every buffered field owns
≥1 identifier token in the struct's token range, so the token span bounds the count). The
`< MAX_BF` cap guards became `< bfCap`. Nested-function growth was tried first but hit the
"too many params after capture" limit (17 captured arrays), so pre-sizing is used instead.

## Acceptance — MET

- Repro returns 42; boundary indices 255/256/257/1000/16999 all correct.
- C-conformance 220/220, nested/anon struct smoke correct, self-host byte-identical.

## Note

Not as rare as first thought: 256 fields is reachable in generated / large C structs, and
the failure is SILENT (wrong value, no diagnostic).

## Log
- 2026-07-18 — resolved, commit fafcb26b.
