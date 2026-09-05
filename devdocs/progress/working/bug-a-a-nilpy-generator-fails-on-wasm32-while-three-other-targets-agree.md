---
track: A
prio: 40
type: bug
blocked-by: []
status: working
summary: "A NilPy generator (`yield` in a `while`, driven by `for x in g(4)`) prints `Unhandled exception` and fails to run on wasm32, while native, i386, arm32 and aarch64 all print 6. The build exits 0 and prints `ok:`. Reproduced at 6f86e8f48 / binary fcc5ad9a29a6. This ticket ORIGINALLY claimed default arguments and constructors were broken too; they were, at an older binary, and were fixed in 34179225a..6f86e8f48 before this was filed -- see the correction below."
owner: frankwasm
---

# A NilPy generator fails on wasm32 while three other targets agree

```python
def g(n):
    i = 0
    while i < n:
        yield i
        i = i + 1
s = 0
for x in g(4):
    s = s + x
print(s)
```

native / i386 / arm32 / aarch64: `6`, rc=0.
wasm32: `Unhandled exception`, rc=1, `exit with invalid exit status outside of
[0..126)`, backtrace at wasm function 1751. The BUILD exits 0 and prints `ok:`.

Not the double-write bug
([[bug-a-wasm32-emits-a-separate-function-per-compileast-call-so-a-proc-built-in-two-calls-loses-a-body]]):
the rewrite counter prints nothing for this source, and it is proven working on
the same binary — it fires on `procedure Fill(out s: string)` and on
`test/test_managed_var_param.pas`.

## Correction — this ticket was filed with three rows that were already fixed

As first filed it claimed a default argument, two defaults and a user-written
`__init__` also trapped on wasm32 (rc=134), and was ranked 55 on the strength of
"ordinary NilPy is unusable there". **All three pass at 6f86e8f48**, printing the
same values as every other target. Only the generator survives, so the ticket is
retitled and re-ranked to 40.

**How the error was made, because it is the reusable part.** The traps were
measured at b0275ecc1 and were real then. Between that and filing I pulled to
6f86e8f48 and rebuilt — and re-ran the six shapes only to read the REWRITE
COUNTER, never to re-read whether they still failed. So a stale run outcome
travelled beside a fresh instrument reading, in the same table, and the stale
half looked as current as the fresh one. The fix that landed in between is
somewhere in 34179225a..6f86e8f48, which contains two wasm32 commits
(`8fb2668c0`, `9b67b266d`); NOT bisected, so this names a range and not a cause.

Caught by franka-29, who could not reproduce a single failing row from the
descriptions and said so instead of assuming its own minimisation was at fault.

The causal story the first filing gave — that these shapes call one of the two
bodies emitted as `unreachable` (`PyBindHostKwArgs`,
`PyBoundFnCallvnMaskBody`) — was INFERENCE from the census line and was never
traced. Those two bodies are present in PASSING builds too, so their presence
was never the discriminator. Whether the generator reaches one of them is open
and is the first thing to check here.
