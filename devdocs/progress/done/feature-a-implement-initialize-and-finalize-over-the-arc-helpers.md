---
track: A
prio: 50
type: bug
owner: claude-A
blocked-by: []
summary: "RE-TYPED 2026-08-19 feature -> bug: MEASURED against FPC 3.x, `Finalize(s)` on an AnsiString leaves `len=5 [hello]` where FPC prints `len=0 []` — FPC-shaped code compiles, runs, and silently does not do what it says. The fix is unchanged: implement Initialize()/Finalize() over the ARC release helpers pxx already emits at scope exit. Zero in-tree callers, so no regression risk; the helpers already exist, so this is a mapping, not new machinery. Supersedes feature-pascal-initialize-finalize-intrinsics, whose premise is wrong."
status: done
---

# Implement `Initialize()` / `Finalize()` over the ARC helpers

**Implements [[decide-finalize-noop-vs-refusal]]** (user, 2026-08-19: *"if a programmer
wants to `Shoot.Foot()` it is able to — that is Pascal design in its purest. So yes,
Finalize should be implemented."*).

**Supersedes [[feature-pascal-initialize-finalize-intrinsics]]**, which asserts the
intrinsics are *missing*. They are not: `Finalize` is parsed, its arguments consumed, and
an empty sequence emitted (`compiler/parser.inc:23122`). Correct or close that ticket.

## What is wrong today

`Finalize(s)` leaves the value **intact** where FPC empties it — a documented v1 shortcut,
not an oversight. Its own comment records the accepted cost: *"a Finalize-reliant container
leaks managed elements until this maps onto the ARC release helpers."*

That is the failure shape the dialect work exists to remove: FPC-shaped code compiles,
runs, and quietly does not do what it says.

## What to build

`Finalize(x[, n])` = **for each managed field of `x`: release the reference, then nil the
field.** That is the *same* operation already emitted at scope exit, driven by a record
layout the compiler already knows — so **map onto the existing ARC release helpers rather
than writing new machinery.** The parser comment names this as the intended route.

`Initialize(x[, n])` = **zero the managed fields into a valid empty state**, without
releasing (the incoming bytes are not references — that is the whole point).

Two properties to preserve, both load-bearing:

- **Finalize nils after releasing, so it is idempotent.** A second `Finalize` on the same
  record decrements nothing. Do not lose this; it removes the obvious footgun.
- **It releases a REFERENCE, not the object.** If the string had refcount 3 because it was
  copied elsewhere, `Finalize` takes it to 2 and the copies stay valid.

## Why these exist at all — the case scope does not cover

Scope-exit cleanup covers variables the compiler declared. It emits nothing for a record
conjured from `GetMem`, which is just bytes to it:

```pascal
p := GetMem(SizeOf(TRec));   { raw bytes — the AnsiString field holds garbage }
Initialize(p^);              { now a valid empty state }
p^.Name := 'hello';          { safe ONLY because the field was nil'd }
Finalize(p^);                { release the string and the dynamic array }
FreeMem(p);
```

Skip `Initialize` and the assignment decrements a refcount through a garbage pointer — the
access violation. Skip `Finalize` and `FreeMem` drops the reference without decrementing —
a leak. Same hazard for `FillChar(rec, SizeOf(rec), 0)` over managed fields, which is the
one that catches careful people because it looks like the obvious "clear this record".

## In-tree beneficiary — do this one as part of the work

`lib/rtl/typinfo.pas:315` does `obj := GetMem(sz)` and then **hand-zeroes the instance**,
with a comment explaining that `GetMem` may hand back reused non-zero heap. That is
`Initialize` written out by hand because the intrinsic was unavailable. Replace it once the
intrinsic works — it is the proof the feature is not hypothetical.

## Risk

**Zero in-tree callers** of either intrinsic (measured 2026-08-19: the single `Finalize`
grep hit is the parser's own definition; `Initialize` has none). So nothing depends on the
current no-op and nothing can regress from implementing it.

## Gate

Track A: `make compiler/pascal26` (the byte-identical self-host fixedpoint) + a repro that
proves a `Finalize`d field is actually emptied and that a copy taken beforehand survives +
`tools/gate.sh quick`.

## Triage 2026-08-19 (Track D re-triage pass, pin v363) — RE-TYPED feature -> bug

Measured against the oracle rather than reasoned about:

```pascal
s := 'hello'; Finalize(s); WriteLn('len=', Length(s), ' [', s, ']');
```

| | output |
| --- | --- |
| pxx, pin v363 | `len=5 [hello]` |
| FPC 3.x (`-Mobjfpc`) | `len=0 []` |

The word in `type:` was the ranking error the re-triage mandate is about:
"feature" reads as optional, and this is a **silent wrong result** in
FPC-shaped code — the exact shape this repo's escape rule promotes to a bug
regardless of how it was filed. Nothing about the *work* changes; only its
class and how it ranks. The scope, the two load-bearing properties
(idempotent, releases a reference not the object) and the zero-in-tree-callers
argument all stand as written.

## 2026-08-21 — implemented; output is byte-identical to FPC

### Result

The triage table's row is now the other way round, diffed against the oracle
rather than reasoned about — the whole 8-line program in
`test/test_initialize_finalize.pas` matches FPC 3.x `-Mobjfpc -O-` output
**exactly**, including the `GetMem` + `Initialize` + `Finalize` + `FreeMem`
sequence this ticket exists for.

| | `Finalize(s)` on `'hello'` |
| --- | --- |
| pxx, pin v363 | `len=5 [hello]` |
| pxx, now | `len=0 []` |
| FPC 3.x | `len=0 []` |

### What it is built from

Two runtime helpers in `compiler/builtin/builtinheap.pas`, over the **same
layout descriptor** scope-exit release already walks — so this is wiring, as the
ticket said, not new machinery:

- `PXXRecordZeroManaged` — store a valid empty state into every managed member,
  releasing nothing. Its own walk because two callers want it for opposite
  reasons (see below).
- `PXXRecordInitialize` = that walk. `PXXRecordFinalize` = `PXXRecordRelease`
  then that walk.

`AN_MANAGED_INIT` (97) dispatches on the lvalue's type. `PXXRecordRelease`
releases but does **not** nil, which is fine for scope exit (the storage dies)
and not fine here — the zeroing pass is what makes Finalize idempotent.

Both load-bearing properties hold and are asserted:
- **nils after releasing** → `again len=0`, and the record's `namelen=0` after a
  second `Finalize`.
- **releases a REFERENCE, not the object** → `keep=[world]` survives.

And `n=3` after the record `Finalize`: unmanaged members are untouched, as in
FPC. That is exactly the line between `Finalize` and `FillChar`.

### Finalize of a STRING is `x := ''` — and that is not a shortcut

Assignment already releases the old reference and stores the new one. That IS
Finalize's definition, down to both properties. So the parser desugars it and the
whole thing reuses the path every assignment in the language exercises.

This is not academic tidiness. The first version hand-built the release in IR —
`PXXStrDecRef(IR_LOAD_MEM(IRLowerAddress(x)))` — and **segfaulted**, passing the
string's CONTENT where its handle belonged (`rdi = 0x6f6c6c6568`, which is
`"hello"`). The desugared version was right first time.
`normalise-dont-special-case.md`, earning its keep.

`Initialize` of a string cannot take that route — an assignment would RELEASE the
old handle, and Initialize's entire premise is that the incoming bytes are not a
reference. It stays a raw zero store.

### Refused rather than silently accepted

- `Finalize(x, n)` — the element-count form. Accepting and ignoring it would put
  the silent no-op straight back, in the one shape that leaks an array's worth
  of references instead of one.
- A **bare** dynamic array or variant lvalue: compile error naming
  [[feature-a-finalize-for-bare-dynarray-and-variant]]. The dyn-array release
  helper needs a per-symbol element descriptor, and `SYM_RTTI_DATAREF_BASE` is
  declared in `defs.inc` but **has no fixup branch**, so there is no IR-level
  route to it. A record *containing* one is fully handled, and `a := nil` is the
  workaround, so the gap is narrow.

Unmanaged types stay legal no-ops (FPC parity) — a generic container that
finalizes every element type has to compile for those.

### The in-tree beneficiary does NOT hold up — checked, not assumed

The ticket says `lib/rtl/typinfo.pas:315` is *"`Initialize` written out by
hand"*. It is not. `CreateInstance` zeroes the **whole instance** (`while i < sz`
over every byte) because unmanaged fields like `FHandle` must be nil too — its
own comment says so. That is `FillChar(obj^, sz, 0)`, and `Initialize`
deliberately does **not** touch unmanaged members.

So replacing it would have been a behaviour change dressed as a cleanup, in
Track B's file-lane, in the direction the ticket meant to prevent. Left alone.
(A `FillChar` for the hand loop would be a fair readability tidy for Track B; it
is not this ticket's business.)

### Also checked

A user proc named `Finalize` still wins (`user Finalize 7`) — the existing
shadowing guards were kept, so this does not become a reserved word.

### Gate

`make compiler/pascal26` (byte-identical fixedpoint) + FPC differential above +
`tools/gate.sh quick`. The Makefile assertion is the FPC-identical block, with a
comment per row saying which way it can be wrong.

## Log
- 2026-08-21 — resolved, commit ff29a3920.
