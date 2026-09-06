---
track: B
prio: 35
type: feature
blocked-by: []
status: open
owner: ""
---

# The RTLEvent family is absent from the threading RTL

`PRTLEvent`, `RTLEventCreate`, `RTLeventSetEvent`, `RTLeventWaitFor`,
`RTLEventResetEvent` and `RTLEventDestroy` do not exist in `lib/rtl` — measured
2026-09-06 at compiler 0d77c1e48ea4, `unknown type: PRTLEvent` with `cthreads`
on the uses line.

## It is a HOLE IN AN OTHERWISE PRESENT SURFACE, which is why it is worth a row

The rest of FPC's threading surface is there and tested: `BeginThread`,
`WaitForThreadTerminate`, `EndThread`, `TThreadID`, `TThreadFunc` and a native
`TThread` (`lib/rtl/palthreadobj.pas`, `lib/rtl/cthreads.pas`,
`test/lib_fpc_thread_surface.pas`, whose own header records that the missing
piece was "the NAMES and SHAPES" rather than the machinery —
`compat-pascal-thread-api-surface-differs-from-fpc`). RTLEvent is the one
FPC-portable primitive a threaded program reaches for that has no pxx spelling
at all, so a source using it needs an `{$IFDEF}` in exactly the place that
compat ticket exists to remove.

It is the ordinary FPC idiom for "wait until the worker has done its thing"
without a busy loop, and both corpus rows that use threads use it:
`tclass16.pp` and `terecs20.pp` (see
`feature-p-threadvar-is-not-supported-at-any-scope`, which those rows are also
gated on — this ticket alone does not burn either).

## Shape

A thin wrapper over what the PAL already has (a mutex + condvar, or an
eventfd/futex on Linux), in `palthreadobj.pas` beside `BeginThread`. `PRTLEvent`
is an opaque pointer in FPC and should stay opaque here.
