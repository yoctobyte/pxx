---
track: A
prio: 70
type: bug
blocked-by: []
summary: "EmitManagedLocalCleanupForTarget has no CurProcIsStackless guard, so a generator step function releases its managed locals on EVERY yield — and those locals ARE the generator's live state. x86-64's EmitManagedLocalCleanup exits early for exactly this reason; the five cross arms never got it. A 12-line NilPy generator whose string local survives a yield SIGSEGVs on i386 and arm32 and prints corrupted strings on aarch64, against correct x86-64 output."
status: open
---

# A managed local that survives a yield is released at every yield (cross only)

- **Track A.** Measured 2026-09-04 by frankb-78 while adding the `tyClass` arm
  to the five cross arms of `EmitManagedLocalCleanupForTarget`
  (`bug-a-cross-backends-neither-retain-into-a-variant-nor-release-a-class-local-and-the-two-must-move-together`).
  Found because that arm needed the guard and the guard was not there.

## The repro

```python
def gen(k):
    acc = ""
    n = 0
    i = 0
    while i < k:
        acc = acc + "x"
        n = n + i * 1000000007
        yield acc + "|" + str(len(acc)) + "|" + str(n % 97)
        i = i + 1

out = []
for v in gen(6):
    out.append(v)
print(out)
```

| target | output |
| --- | --- |
| CPython | `['x\|1\|0', 'xx\|2\|41', 'xxx\|3\|26', ...]` |
| x86-64 | identical to CPython |
| i386 | **SIGSEGV** |
| arm32 | **SIGSEGV** |
| aarch64 | `['x\|1\|0', '\x00\x00\|3\|41', '\x00\x00\|3\|26', ...]` — wrong value, no crash |

Compiles fine on all four; the divergence is at runtime.

## The cause, and why x86-64 is the one that is right

`EmitManagedLocalCleanup` (x86-64, `symtab.inc`) opens with

```pascal
  if CurProcIsStackless then Exit;
```

and its comment explains it: a stackless generator step function RETURNS at
every yield and is re-entered at the next one, so its locals are not going out
of scope on that path — they are the generator's live state, checkpointed into
the heap instance and restored on resume. Releasing them there frees the very
objects the instance still points at.

`EmitManagedLocalCleanupForTarget` (`ir_codegen.inc`) has five arms — i386,
arm32, aarch64, xtensa, riscv32 — and **not one of them has that guard.** Each
opens with `if CurProc >= 0 then` and walks straight into the release chain, so
every string, variant, promo-int, record and dynamic-array local of a step
function is released at each yield. Pascal never sees it (its class locals are
not refcounted and it has no NilPy generators), which is why the hole survived.

wasm32 releases in `WasmEmitManagedLocals(release)` instead and is **unchecked
by this ticket** — it needs the same question asked of it.

## The fix

Hoist the same early exit into `EmitManagedLocalCleanupForTarget`, beside the
`TARGET_WASM32` exit that is already there:

```pascal
  if CurProcIsStackless then Exit;
```

The `tyClass` arm added by the sibling ticket carries `(not CurProcIsStackless)`
inline as a stopgap, so it is already correct; that clause becomes redundant
once the whole-function guard lands and should be deleted in the same commit,
with the comment's stopgap paragraph.

## The guard this needs

The repro above IS the positive control — it must go from SIGSEGV to CPython's
output on i386 and arm32 and from corrupted strings to correct on aarch64. Wire
it on all four targets; x86-64 is the oracle and is already green, so an
x86-64-only row would pass before and after and prove nothing.
