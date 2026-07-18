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

## Suspect

A 16-bit field-offset wrap somewhere in C struct member lowering: 67996 mod 65536 =
2460, which aliases a low field. Any struct whose fields cross the 64 KB offset boundary
would be affected. Accessing only low fields (offset < 64 KB) of the same 20000-field
struct is correct (verified — that's the UField-growth regression test), so it is the
OFFSET, not the field count / the dynamic UField pool.

## Fix

Audit the C field-offset path (UFldOff_, the `.field` lowering, IR offset operands) for
a 16-bit truncation; widen to 32-bit. Cross-check the Pascal record path (a Pascal
record with a field past 64 KB may share the bug).

## Acceptance

- The repro returns 42; a `test/*.c` regression accessing a field past 64 KB offset.
- Gate: C-conformance stays 220/220 + self-host byte-identical.

## Note

Astronomically rare in real code (a single struct > 64 KB), hence low prio; filed so the
UField-growth regression test's deliberate low-field access is documented, not a smell.
