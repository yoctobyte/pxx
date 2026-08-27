---
prio: 60
track: P
owner: frankA
---

# Two generic templates cannot both declare a nested type of the same name

- **Type:** bug (silent wrong resolution) — **Track P** (Pascal frontend, generic
  specialization).
- **Status:** done
  [[bug-p-a-nested-type-may-name-a-field-after-an-enclosing-type-parameter]].
- **Pre-existing:** reproduced identically on the **pinned** binary, so it is not
  a consequence of that fix.

## Repro

```pascal
type
  generic TA<K, V> = class
  public type TPair = record aa: K; bb: V; end;
  private FA: array of TPair;
  public procedure Put(const a: K; const b: V);
  end;
  generic TB<K, V> = class
  public type TPair = record cc: K; dd: V; end;   { same nested NAME }
  private FA: array of TPair;
  public procedure Put(const a: K; const b: V);
  end;
```

`TB.Put`'s `FA[High(FA)].cc := a` → **`pascal26: error: "cc": no such member on
this record/class`**. `TB`'s `TPair` resolved to **`TA`'s**, whose fields are
`aa`/`bb`. FPC 3.2.2 compiles and runs it (prints `11`).

No type-parameter name collision is involved — the field names here are all
distinct from `K`/`V`, which is what separates this from the ticket it was found
under.

## Why it matters

`TPair` is not an arbitrary example. Every dictionary-shaped generic in
Generics.Collections declares a nested `TPair`, so **corpus rung 6
(rtl-generics) cannot pass while this stands** — and the failure mode is a
member-not-found error pointing at the second template, with nothing naming the
first.

## Where to look

Nested types inside a template are presumably registered under a name derived
from the nested identifier without the enclosing template's identity, so the
second registration collides with (or is shadowed by) the first. Compare how
`EmitSpecDecl` / `FindSpecialization` build alias names for the specialization
itself — those DO carry the template name (`TBase$Integer`), which is the shape
the nested type wants too.

## Gate

Track P: `make compiler/pascal26` (self-host fixedpoint) + the repro matching
`fpc -O2` output, plus `tools/run_fgl_corpus.sh` still 7/7. Add the repro as a
test with an `.expected`.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
