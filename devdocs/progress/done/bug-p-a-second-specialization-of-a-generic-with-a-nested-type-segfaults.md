---
prio: 60
track: P
owner: frankA
---

# A second specialization of a generic that has a nested type SEGFAULTS at runtime

- **Type:** bug (segfault) — **Track P** (Pascal frontend, generic
  specialization) — may prove to be Track A once the cause is known.
- **Status:** done
  [[bug-p-two-generic-templates-cannot-share-a-nested-type-name]].
- **Pre-existing:** reproduced identically on the **pinned** binary.

## Repro

```pascal
type
  generic TD<K, V> = class
  public type TPair = record aa: K; bb: V; end;
  private FA: array of TPair;
  public procedure Put(const a: K; const b: V);
        function KeyAt(i: LongInt): K; function Count: LongInt;
  end;
type
  TSI = specialize TD<String, LongInt>;
  TII = specialize TD<LongInt, LongInt>;   { the SECOND one }
var a: TSI; b: TII;
begin
  a := TSI.Create; a.Put('one', 1); WriteLn(a.Count, ' ', a.KeyAt(0));  { prints "1 one" }
  b := TII.Create; b.Put(10, 20);   WriteLn(b.Count, ' ', b.KeyAt(0));  { SIGSEGV }
end.
```

It **compiles clean** and the first specialization runs correctly. The second
segfaults — exit 139, after the first line has printed. `fpc -Mobjfpc` prints
`1 one` / `1 10`.

## Boundary

- Field names deliberately do NOT collide with `K`/`V`, and the nested type name
  is used by only one template — so this is independent of the two adjacent
  nested-type defects.
- One specialization of the same template: fine.
- The distinguishing ingredient is the **nested type plus a second
  specialization**; a generic with no nested type specializes twice happily
  (`gmain` in the same session: `TBox<LongInt>` and `TBox<String>` together).

## Why it matters

A compile-clean SIGSEGV is the worst failure shape here — no diagnostic, and it
appears only when a second specialization is added, so it will look like the
caller's fault. Generics.Collections specializes the same templates many times
over, so **rung 6 will hit this immediately after the shared-nested-name defect
above**, and the two should probably be investigated together: both are about a
nested type's identity not being per-specialization.

## Where to look

Likely the nested type is registered once and shared across specializations, so
the second specialization's instance reads the first's layout (element size,
managed-field descriptor). A wrong `TPair` size for `array of TPair` would give
exactly this: correct first instance, wild pointer on the second. Confirm with
`PXXDBG=a.ir` on `Put` for both specializations and compare the element size and
field offsets.

## Gate

Track P: `make compiler/pascal26` (self-host fixedpoint) + the repro running and
matching `fpc -O2`, plus `tools/run_fgl_corpus.sh` still 7/7. Add the repro as a
test with an `.expected`.

## Log
- 2026-08-27 — resolved, commit 7ee75329e.
