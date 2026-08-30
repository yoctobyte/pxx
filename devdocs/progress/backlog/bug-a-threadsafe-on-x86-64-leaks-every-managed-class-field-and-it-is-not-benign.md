---
track: A
prio: 55
type: bug
blocked-by: []
summary: "`--threadsafe` on x86-64 gates PXXClassFinalize's string/dynarray pass off (PXX_TS_HARDLOCK), so EVERY managed field of EVERY destroyed class instance leaks. Documented as a `pre-existing benign leak` and never measured: a plain Pascal program creating and Freeing 200k instances with one 2000-byte AnsiString field goes 392 kB -> 398336 kB. A thousandfold, in Pascal, not just NilPy. The word to challenge is `benign`."
status: backlog
owner: frankS
---

# --threadsafe leaks every managed class field on x86-64, and "benign" was never measured

- **Track A** (heap lock discipline + `compiler/builtin/builtinheap.pas`).
  Measured 2026-08-31 by frankS while verifying that two NilPy leak fixes held
  under `--threadsafe`; they do, and this was underneath them.
- Not a regression and not new. It is the RESIDUAL that
  `bug-a-class-managed-fields-not-finalized-on-destroy` (done) recorded as kept
  out on purpose — *"the hardlock string case keeps the pre-existing benign
  leak instead of racing the allocator"*. That was the right call at the time.
  What was never done is put a number on it.

## The repro — plain Pascal, no NilPy

```pascal
program tsleak;
type THolder = class S: AnsiString; constructor Create(base: AnsiString); end;
constructor THolder.Create(base: AnsiString); begin S := base + '!'; end;
var h: THolder; k, i: Integer; b: AnsiString;
begin
  b := ''; for i := 1 to 2000 do b := b + 'x';
  k := 0;
  for i := 1 to 200000 do begin h := THolder.Create(b); k := k + Length(h.S); h.Free; end;
  WriteLn(k);
end.
```

| build | max RSS |
| --- | --- |
| `pascal26 -Fulib/rtl tsleak.pas` | **392 kB** |
| `pascal26 -Fulib/rtl --threadsafe tsleak.pas` | **398336 kB** |

Same source, same printed answer (`400200000`), 1016x the memory. It is the
whole field payload, every instance, forever.

## Mechanism, and it is one `{$ifndef}`

`PXXClassFinalize` (builtinheap.pas) ends with

```pascal
{$ifndef PXX_TS_HARDLOCK}
  PXXRecordRelease(inst, desc);
{$endif}
```

`PXX_TS_HARDLOCK` is defined by `--threadsafe` on x86-64 only (lexer.inc:1168).
The stated reason is real: on that target the heap lock is the **codegen-emitted
BSS spinlock**, which Pascal-level runtime code cannot take, so releasing from
Pascal would race the allocator. The kind-4 (COM interface) pass above it is
NOT gated and does run.

## Two directions, neither verified — do not pick one from this ticket

1. **Give Pascal a way to take the lock.** The blob route already exists in the
   opposite direction: `AnsiStrReleaseAddr` is a codegen-emitted blob that
   acquires and releases the spinlock around exactly this kind of work, and
   scope-exit epilogues call it under `--threadsafe` today. If a Pascal-callable
   acquire/release pair is expressible, the `{$ifndef}` goes away. **First
   question to measure: what else already frees from Pascal under
   `--threadsafe`, and why is that safe?** If the answer is "quite a lot", the
   guard is over-broad rather than load-bearing.
2. **Emit the field walk as codegen** at the `Free` desugar, where the lock is
   reachable. Correct by construction, and a much larger change — it duplicates
   a walker that exists once today.

## Also in scope, same constraint, named in the done ticket

RECORD COM-interface fields are the same benign-by-assertion leak under the
same lock. Whoever measures one should measure the other.

## Why this is filed rather than fixed

The `{$ifndef}` is one line and deleting it is a data race, not a fix. The
work is establishing which of the two directions is sound, and that is
measurement plus a lock-discipline judgement — not a microfix.
