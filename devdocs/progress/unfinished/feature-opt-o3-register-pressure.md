
---

## 2026-08-29 — item 3 extended to FLOAT residents. LANDED (`da88ba9d7`).

A tyDouble local resident in xmm8..13 dual-writes its frame slot on every store.
At `-O3`, in a body with no exception frame, nothing reads that slot, so the
store is dead. This deletes it. Entirely inside `EmitStoreVar`'s float
skLocal/skParam arm in `symtab.inc`; `ir_codegen.inc` untouched.

### Priced before it was built, and it priced differently from the last item

| population | int residents | float residents |
| --- | --- | --- |
| `compiler.pas` | 3049 | **21** (0.7%) |
| chess | 388 | 19 (4.7%) |
| mandelbrot | 378 | **49 (11.5%)** |
| jsondemo | 1124 | 57 (4.8%) |
| NilPy xml.etree / collections.abc / codecs | — | 3 / 6 / 3 |

The count alone would not have justified it — the exception gate died at a
comparable share. What justified it is **where**: mandelbrot's
`EscapeCountLimit` is the Mandelbrot iteration itself, it holds six float
residents (`zre zim zr2 zi2 cre tmp`), and **nine of that loop's fourteen
`IR_STORE_SYM`s target them**. The driver-loop pattern that killed the exception
gate was looked for and is not here.

**The raw 146 is deflated on purpose.** A large share sits in the RTL float
formatting path — `FloatToStrSig`, `FloatToStrF`, `FloatToExpStr`,
`PXXWriteFloatNat`, `PXXWriteFloatFixed`, `ParseFloatCore` — which links into
every program that prints a real. That is **Track F** subject matter and low
prio by the standing ruling: the subject is float formatting, regardless of the
fact that the mechanism here is a store elision. The case rests on the
non-formatting residents.

### First confirmed the item existed at all

`ResidentSlotIsDead` reaches float residents never: it goes through
`ResidentRegOf`, which scans `RcResidentSym` (r12-r15). Float residents live in
`FrResidentSym` behind `FloatResidentXmmOf`. So all 146 kept the dual-write
unconditionally. Measured, not inherited from this ticket's own known-unknown
list.

### The probe was defective and its first result was worthless

Whole-program poison, three programs, all clean, control fires. That result was
nearly reported. It was wrong.

The control moved **`WithExcFrame`** — a body the `RcProcHasExc` gate excludes
and which therefore has **zero poison sites**. A row that cannot move, moved.

Cause: the RTL float formatting path is itself full of float residents, and
every `Writeln` of a real goes through it. A whole-program poison run corrupts
the **printer**, so every line of output moves whether or not that line's own
residents were read.

> **The instrument was measuring its own printer** — and it reads exactly like a
> working control.

Fixed with `PXXDBG=a.poisonslot:<Proc>`, restricting poisoning to one body, for
both poison probes. Only then does a per-case reading mean anything.

**The catch came from a case whose expected direction was already known.** Not
from suspecting the probe. That is the argument for always including a case that
*must not* move: it is the only row whose failure is unambiguous.

### Result, per proc — poison alone vs poison + `a.poisonctl`

| proc | poison | control | sites |
| --- | --- | --- | --- |
| Recurrence | clean | visible | 11 |
| ValueParam | clean | visible | 3 |
| AcrossInternal | clean | visible | 4 |
| AcrossIndirect | clean | visible | 4 |
| AcrossMath | clean | visible | 4 |
| NarrowTypes | clean | visible | 2 |
| ViaGlobal | clean | visible | 2 |
| mandelbrot `EscapeCountLimit` | clean | visible | — |
| **WithExcFrame** | clean | **BLIND** | **0** — `RcProcHasExc`, correct |
| **RefCaller** | clean | **BLIND** | **0** — by-ref, never resident, correct |

The two blind rows **print their zero site count** rather than leaving it
inferred, which is the same remedy as the harness fix earlier today: a clean row
with zero comparands and a clean row with eleven are otherwise indistinguishable.

### Negative results worth keeping

- **`FloatPoolSave`/`FloatPoolRestore` are NOT slot readers.** They round-trip
  the whole xmm8..13 pool through the separate `FxSaveBase` reserved area and
  never touch a variable's own frame slot. This was the reader most likely to
  exist and it does not.
- **`FloatResidencyRefreshAll` has exactly one caller**, the `IR_EXC_ENTER`
  landing pad. `defs.inc`'s comment said extern/indirect calls also refreshed
  through it; that was **wrong when written**, not made wrong by this change, and
  is now fixed. Second stale-comment-as-durable-wrong-answer of the evening.
- **Address-taken locals cannot be residents**: `SymSlotEscapes` gates both the
  int and the float candidate loops, so the escape case needs no separate guard.

### Same gate as the int half, different mechanism — do not narrow it by analogy

Int residents are rolled back because `ExcLongJmp` restores r12-r15 from the
jmp_buf. **xmm8..13 are not in the jmp_buf at all** — the setjmp stub saves no
XMM. The float pool is lost instead because a raise longjmp skips the unwound
frames' save-iff-used epilogue restores; the landing pad then restores the pool
from the try-entry snapshot and calls `FloatResidencyRefreshAll`, which reloads
each resident **from its own frame slot**. Different route, same conclusion, and
anyone narrowing one gate on the strength of the other's mechanism will get it
wrong.

### The measured effect, and a count I could not reconcile

mandelbrot `-O3`: **296 fewer bytes of code** (98337 -> 98041) and **37 fewer
`movsd [rbp+disp32],xmm0`**, both measured on the artifact.

The probe counts **76** skip sites at codegen. Those two should agree and do not.
Ruled out: dead-proc elimination (`procs=788` at both `-O2` and `-O3`) and double
emission (`Recurrence` fires exactly 3 times for its 3 source stores to `zr`; a
minimal proc with 4 stores fires 4). The model that fits both this and a minimal
repro is that ~10 fires per program land in code emitted and then rewound —
**unverified, so every number quoted elsewhere is the binary one.**

**And the reason that discrepancy was chased at all:** earlier in the same
session, 261 poison sites were reported by dividing a 2876-byte size delta by 11.
The real count was 76. The probe could have been asked directly and was not.

> **A count inferred from a byte delta is not a count.** It is the empty-diff
> defect wearing better clothes — a derived number standing in for a measured
> one, and it reads as *more* rigorous rather than less.

### Not timed

The removed store is **off the recurrence** — loads already come from the xmm
register — so unlike int item 3 there is no store-to-load-forwarding latency to
recover and only the throughput arm is in play. Prediction on record before
measuring: small, plausibly under 1.02x, possibly indistinguishable from noise.
Timing needs a quiet box and the coordinator's go-ahead; the code-size result
stands on its own either way.
