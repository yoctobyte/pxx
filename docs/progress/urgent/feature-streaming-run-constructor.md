# feature: RTTI .lfm streaming must run the object's constructor

- **Type:** feature (Track A — compiler RTTI emission + lib/rtl streaming)
- **Status:** urgent
- **Found:** 2026-06-23, dogfooding Eliah's layout via the .lfm streaming loader
- **Severity:** high (design debt) — the current streamer SKIPS constructors, so
  every class with constructor-established state breaks when streamed. Four such
  bugs already shipped stopgaps (`done/bug-lfm-streaming-skips-constructors`);
  more will appear as new streamable widgets are added.

## Problem

`typinfo.CreateInstance` allocates an instance from RTTI (`GetMem` + set VMT)
but does **not** run its constructor; `TReader` then pours in published
properties. So any state a class sets up in `Create` — `TPaintBox.FCanvas`,
`TListBox/TComboBox.FItems`, defaults — never happens. We patched the three
crashing widgets by moving init out of their constructors (Canvas → CreateHandle,
arrays → grow-on-demand) + zeroing the instance. Those are **workarounds**: a
class should be able to rely on its own constructor.

## How FPC does it (for reference)

Virtual constructor (`TComponent.Create(AOwner); virtual`) + class references
(`class of TComponent`) + `RegisterClass`. The reader does
`GetClass(name).Create(Owner)` — a virtual-constructor call dispatched through the
VMT: allocate (`NewInstance`) → run the real derived constructor → then stream
properties. No manual code-pointer fishing; the language feature does it.

We do NOT need to build `class of` to fix this (see Decision).

## Decision — option 1: a constructor pointer in the class RTTI

`GetClass` already returns a `PClassRTTI` that acts as a runtime metaclass. Make
it a real factory:

1. **Compiler:** emit each class's parameterless-constructor **body** entry point
   into a new `TClassRTTI.CtorPtr` field (the body that runs init on an already-
   allocated `Self`, i.e. what `inherited Create` jumps to — NOT the alloc-and-
   init entry).
2. **lib/rtl:** `CreateInstance` (or a new `Construct(cls)`) calls it:
   ```
   obj := GetMem(sz); zero(obj); set VMT;
   if cls^.CtorPtr <> nil then CallCtor(obj, cls^.CtorPtr);  { Self in rdi }
   ```
   `CallCtor` is the call-by-code-pointer already used for setter methods
   (`SetOrdProp` SetKind=1). Then `TReader` streams properties on top.

### Why option 1
- **Zero source changes** — widgets keep plain `constructor Create;`
  (FPC-source-compatible). The Canvas/array stopgaps revert to their constructors.
- **FPC's observable behaviour** (ctor runs → props override) with ~6 lines of RTL
  + one RTTI field, instead of full `class of`/virtual-constructor support.
- Idempotent: these constructors call `HandleNeeded` (`if FHandle=nil`), so
  running them at stream-time then again at Realize is safe.

### The gotcha
Emit/call the constructor **body**, not the allocating entry, or you double-
allocate. The compiler already splits these (that is how `inherited Create` runs
the parent body without re-allocating).

## Alternatives

- **Option 3 (no compiler change, Track B):** a lib factory registry mapping
  class → ctor-thunk, called by `CreateInstance`. Works, but verbose (one
  registration per streamable class, easy to forget — the exact bug class we hit).
  Fallback if option 1's RTTI change is undesirable.
- **Full `class of` + virtual constructors:** the "real" FPC path; bigger language
  feature, tracked separately (`backlog/feature-object-reference-type`,
  `feature-metaclass-descendant-enforcement`). It would REUSE `CtorPtr` as its
  runtime, so option 1 is a prerequisite, never wasted. Do NOT gate this fix on it.

## Acceptance

A streamed instance has its constructor run before properties stream: a streamed
`TPaintBox` has a Canvas, a streamed `TListBox` has its arrays, defaults are set.
Then the PCL stopgaps (Canvas-in-CreateHandle, grow-on-demand, the
constructor-skip note) can be reverted to idiomatic constructors. `test_pcl_lfm`
+ a new "stream + construct" gate stay green.

## Track B impact (now)

Eliah builds with the stopgaps in place (working). The `TEliahForm` layout-from-
lfm conversion (`backlog/feature-eliah-from-lfm`) is unblocked by the stopgaps and
does not need this; this feature lets us DELETE the stopgaps and keep widget
constructors idiomatic.

## Background

Full design discussion + the FPC analysis: `docs/developer/lfm-streaming-and-constructors.md`.
