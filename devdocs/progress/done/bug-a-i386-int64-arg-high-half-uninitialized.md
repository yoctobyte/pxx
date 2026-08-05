---
summary: "i386: widening a 32-bit value into an Int64 argument leaves the HIGH half uninitialized — silent garbage, and the garbage changes with surrounding code"
type: bug
track: A
prio: 75
owner: claude-A
---

# i386: an Int64 argument's high half is left uninitialized (silent garbage)

- **Type:** bug — Track A (i386 backend / argument materialization)
- **Status:** done
- **Opened:** 2026-08-04
- **Found by:** Track B, cross-targeting `test/lib_format_ge.pas` after a float
  formatting fix. **Pre-existing** — the unmodified file and unmodified RTL fail
  identically on i386.

## Symptom

`i386 only`. x86-64, arm32 and aarch64 are all correct.

```pascal
procedure ShowI64(v: Int64); begin writeln(v); end;
var e: Integer;
begin
  e := -1;
  ShowI64(Abs(e));        { prints -133143986175, not 1 }
end.
```

The low 32 bits are always right; the **high 32 bits are whatever was already
in the slot**. `-133143986175` is `0x1F_00000001` sign-flipped — the value 1
with garbage above it.

## The tell: the garbage MOVES

Running the same matrix twice with different surrounding statements changed
*which* rows failed — `ShowI64(Length('abc'))` was wrong in one arrangement and
right in the next, with no change to that line. That is the signature of an
uninitialized slot rather than a wrong extension instruction: the result depends
on what the previous code happened to leave there.

Consequence for whoever picks this up: **do not trust a passing case**. A form
that looks correct may simply have inherited a zero high half. Only the failures
are evidence.

## Matrix (one arrangement; the ok/WRONG split shifts, the failures are real)

| form | i386 |
| --- | --- |
| `x: Int64; x := e` | ok |
| `x := TakeI64(e)` (result into a var first) | ok |
| **`writeln(TakeI64(e))`** (Int64 result used directly as an argument) | **WRONG** |
| `ShowI64(e)` (plain variable) | ok |
| **`ShowI64(Abs(e))`** (builtin result as the argument) | **WRONG** |
| `ShowI64(MyAbs(e))` (user function returning Integer) | ok |
| `ShowI64(-e)`, `ShowI64(e+0)`, `ShowI64(Ord('a'))` | ok |
| **`x := TakeI64(Abs(e))`** | **WRONG** |

The two reliable triggers are **a builtin's Integer result passed where an
`Int64` is expected**, and **an `Int64` function result used directly in an
argument position** without passing through a variable. Storing to a variable
first fixes both, which is consistent with the store path extending correctly
while the argument-materialization path does not.

## Why it is urgent

- **Silent.** No error, no warning, plausible-looking output.
- **Nondeterministic in effect**, so it will reproduce inconsistently and
  reduce badly.
- **`IntToStr` takes an `Int64`.** So `IntToStr(Abs(n))` — an entirely ordinary
  line — silently produces a wrong number on i386. That is how this was found:
  `Format('%e', ...)` printed `3.333E--4294967295` for an exponent of -1,
  because `IntToStr(Abs(e10))` received garbage.

## Repro

```
cat > /tmp/r.pas <<'P'
program r;
procedure ShowI64(v: Int64); begin writeln(v); end;
var e: Integer;
begin e := -1; ShowI64(Abs(e)); end.
P
./stable_linux_amd64/default/pinned --target=i386 /tmp/r.pas /tmp/r_386 && qemu-i386 /tmp/r_386
# prints garbage; x86-64/arm32/aarch64 print 1
```

## Test coverage note

`test/lib_format_ge.pas` reproduces this on i386 today (6 rows) and is a ready
regression target — but `lib-test` runs **x86-64 only**, which is exactly why a
32-bit codegen bug in a widely-used RTL path went unseen. Worth considering
whether some part of `lib-test` should run under qemu for the 32-bit targets;
this is the second 32-bit-only silent-value bug found by hand-cross-checking
(see bug-32bit-truthiness-high-half, bug-64bit-named-const-truncated-32bit-targets).

## Resolution (2026-08-05)

**Three sites, one rule, and the ticket's framing was wrong in two useful ways.**

The ticket called it "argument materialization" and said the matrix shifts
unpredictably. Both readings came from measuring only the symptom. The actual
rule is narrow and the matrix is fully deterministic once you add the missing
variable: **optimisation level**.

- `-O0` and `-O1`: every row correct.
- `-O2` and `-O3`: rows fail.

That is the missing variable, and it explains the "garbage moves" tell without
any nondeterminism: at `-O2` the **inliner** collapses an `Int64`-returning
helper down to a bare 32-bit load, so the IR ends up with a node whose TYPE says
`Int64` while its PRODUCER only ever wrote `eax`. Which rows fail then depends
purely on which helpers got inlined, which is why rearranging statements
appeared to move the failures. `PXXDBG=a.inline` shows
`RETAIN __pxxAbsInt shape=2` — `Abs(e)` becomes `if e < 0 then -e else e`, typed
`Int64`.

Three consumers assumed "the node's type says 64-bit, therefore edx:eax already
holds the value" and read whatever the previous code left in `edx`:

| site | shape that reaches it |
| --- | --- |
| `IR_WRITE` 64-bit branch | `writeln(F64(e))` — Int64 fn inlined to a 32-bit load |
| `IR_NEG` 64-bit branch | `Abs(e)` on an Integer — `neg eax / adc edx,0 / neg edx` folds stale edx in |
| `IR_NOT` 64-bit branch | same shape via `not Int64(e)` |

Fix: each now uses **`EmitNode64_386`** instead of `IREmitNode386`. That helper
already existed for exactly this and widens from the VALUE node's own type (`cdq`
when signed, `xor edx,edx` when not), and is a no-op when the operand is already
64-bit. The call-argument paths were already doing this correctly — which is why
`ShowI64(e)` worked and made the bug look like an argument problem. It was the
opposite: arguments were the one place that got it right.

Audited the whole backend for the pattern (`IREmitNode386` followed by a
`Is64Bit386(IRTk[node])` branch); these three were the only occurrences. The two
other `edx:eax` sites (the variadic tail push at 2900, the store at 1535) already
widen explicitly.

**Verified.** The ticket's own repro prints `1`. Its full matrix is correct on
i386 at `-O0/-O1/-O2/-O3`, identical to x86-64. `test/lib_format_ge.pas` — which
the ticket named as a ready regression target, failing 6 rows — now matches
x86-64 exactly.

Locked in as `test/test_i386_int64_high_half.pas`, covering all three sites,
verified identical on i386 / arm32 / aarch64 / riscv32 at `-O1`, `-O2` and `-O3`,
and byte-identical to FPC.

### On the ticket's "do not trust a passing case"

That warning was sound advice for a bug believed nondeterministic, but it is not
needed here: the behaviour is deterministic given (optimisation level, which
helpers inline). Anyone extending this should vary `-O` first — the shape is
invisible at `-O1`.

**Gate:** `testmgr --tier quick` 15/15 green; `tools/selfhost_fixedpoint.sh`
converges in 2 rounds from `pinned` and agrees with `compiler/pascal26`;
`tools/lib_cross_sweep.sh` before/after diffed.

### Cross-sweep

`tools/lib_cross_sweep.sh` before/after: **27 failing rows -> 25**.
`lib_format_ge i386` cleared (the ticket's named target); the other two that
dropped are the known-flaky `lib_dns_cache_facade` and
`lib_http_pool_concurrent`.

One row reappeared, `lib_sockets aarch64` — **not caused by this change, and
provably so**: the diff is confined to `ir_codegen386.inc`, which only executes
under `--target=i386`, so it cannot alter aarch64 codegen. It is a timing flake
(`rc 124` is the sweep's own `timeout 60`, with `bind=FAIL` from a lingering
port under qemu) and it appears in 3 of the 4 sweeps run today, including the
baseline.

## Log
- 2026-08-05 — resolved, commit PENDING-COMMIT.
