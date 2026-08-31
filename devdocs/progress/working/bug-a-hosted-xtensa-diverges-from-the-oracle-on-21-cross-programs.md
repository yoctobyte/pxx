---
track: A+S
type: bug
prio: 40
status: working
found: 2026-08-30
found-by: frankS
owner: frankA
summary: "Hosted xtensa vs the x86-64 oracle. Re-measured 2026-08-31 at compiler db19ff591808: 140 sources, 115 MATCH / 5 DIFF / 20 CFAIL. Of the 5, only 2 are compiler bugs (test_cross_syscall; test_cross_float is Track F) -- 2 are sweep artifacts and 1 is a test-coverage gap, all reconciled below. The slug's `21 cross programs` and the body's `142 sources` are BOTH stale; the denominator is derived from the Makefile and moves."
---

# Hosted xtensa diverges from the x86-64 oracle on 21 of 142 cross programs

> **PREMISE CORRECTED, slug kept (frankA, 2026-08-31).** Neither number in that
> heading survives measurement: the denominator is not 142 and never was, and
> the divergence count is 5, of which 2 are defects in this sweep rather than in
> the compiler. Read the 2026-08-31 section at the bottom, not this table — the
> table below is the 2026-08-30 state and is kept as history.

The first differential sweep xtensa has ever had. Of the 142 sources
`test-riscv32` uses, **55 match the x86-64 oracle exactly** (now wired as
`make test-xtensa`), **66 fail to compile** for xtensa at all, and **21 compile,
run, and produce the wrong answer.** This ticket is the 21.

Sweep conditions: `--target=xtensa --platform=posix --xtensa-soft-mulhigh`,
Call0, `qemu-xtensa` 10.2.1, compiler at `e866cc16d4fe`. Both flags are
load-bearing: without `--platform=posix` syscalls lower to `PAL_ERR_UNSUPPORTED`,
and without `--xtensa-soft-mulhigh` any numeric output SIGILLs.

## The 21

> Note (frankA, 2026-08-30): the `test_cross_managed_aggregate_locals` row
> originally held this program's **raw output bytes**, pasted literally. Four
> of them (`\xac \xc6 \xcc \xbc`) are not valid UTF-8, which made every
> `progress.py` run — `board-md` and `check` alike — die with a
> `UnicodeDecodeError` for **all** agents, since those tools read the whole
> ticket tree. The bytes are evidence, so none were dropped: each is now a
> backslash escape (`\xNN`, `\t` for the tabs), byte-for-byte identical to what
> was captured. Two agents hit this and repaired it independently within the
> same hour, which is itself the argument for the note: the failure surfaces far
> from its cause — every ticket tool dies, naming a byte offset in a file the
> agent running them never touched. Escape binary program output before pasting
> it into a ticket.

| program | xtensa | x86-64 |
| --- | --- | --- |
| `test_arm32_record_byval_wide` | `1 0` | `1 2` |
| `test_array_of_const_types` | `vt0: 42` | `vt0: 42` |
| `test_asm_ifdef_multiarch` | `0` | `42` |
| `test_cross_aggregate_stackargs` | `qemu: uncaught target signal 7 (Bus error) - c` | `3 7 5` |
| `test_cross_dynarray` | `10 20 30 len=3` | `10 20 30 len=3` |
| `test_cross_float` | ` qemu: uncaught target signal 7 (Bus error) - ` | ` 3.5000000000000000E+000` |
| `test_cross_float_return` | `qemu: uncaught target signal 7 (Bus error) - c` | `2.5000` |
| `test_cross_managed_aggregate_locals` | `\x05hello\x06 world\x04text\xac#\t\x08\x04\xc6\x1b\t\x08\x04\xcc#\t\x08\xbc#\t\x08L%\t\x08\x04\x03d%\t\x08` | `hello 42` |
| `test_cross_multidim3d` | `var3d=1476000000 c123=123000000` | `var3d=1476000000 c123=123000000` |
| `test_cross_openarray_string` | `count=2` | `count=2` |
| `test_cross_param_2darray` | `vsum=14` | `vsum=14` |
| `test_cross_stack_params` | `six=123456` | `six=123456` |
| `test_cross_syscall` | `0` | `1` |
| `test_cross_trunc_round_saturate` | `t+1e30=2147483647 r=2147483647` | `t+1e30=9223372036854775807 r=92233720368547758` |
| `test_cross_var_string_param` | `varlen=545267744` | `varlen=5` |
| `test_interface_arc` | `hello` | `hello` |
| `test_interfaces_multi_secondary` | `direct` | `direct` |
| `test_managed_local_release_reuse` | `ok   ansistring local` | `ok   ansistring local` |
| `test_shortstring_trunc` | `aaaa 4` | `aaaa 4` |
| `test_single_in_aggregate` | `qemu: uncaught target signal 7 (Bus error) - c` | `1.5 2.5 3.5` |
| `test_u64_to_double` | `assign-ok` | `assign-ok` |

(First line of output only; several diverge further down.)

## Three clusters, and the first one is a known signature

**1. A heap handle leaking where an integer belongs.** `test_cross_var_string_param`
prints `varlen=545267744` against the oracle's `varlen=5` — and `545267744` is
the *same shape of value* that ansistring `=` returned before
[[bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle]]: a live
heap address rendered as a number. `Length()` of a `var string` parameter is
handing back the handle instead of the length. Start here — it is the cluster
with a known cause nearby, and `firstchar` being garbage in the same run says
the parameter's indirection is what is wrong, not `Length` itself.

**2. Bus errors and segfaults, all involving aggregates or floats:**
`test_cross_aggregate_stackargs`, `test_cross_float`, `test_cross_float_return`,
`test_single_in_aggregate`, and `test_cross_multidim3d` (which prints its first
line correctly, then segfaults on a 3-D array *parameter*). A crash is the cheap
case and these have locations; take them before the quiet ones.

**These are NOT Track F.** They are crashes and wrong control flow that happen to
live in float code — `rank the mechanism, never the datatype`. Float *accuracy*
would be F; a bus error is an ordinary bug.

**3. Quiet wrong values:** `test_cross_syscall` answers `0` where the oracle says
`1`, `test_cross_stack_params` loses arguments past the register set,
`test_shortstring_trunc`, `test_u64_to_double`, the two interface tests. These
are the expensive class — no crash, a plausible number, far from the cause.

## Deliberately not skipped

The 21 are excluded from `make test-xtensa` by NAME, not by a silent filter, and
this ticket is cited in that target's header. A differential that quietly drops
its own failures is precisely how xtensa reached 2026 with a backend nobody had
ever executed.

## Bound

Object-level plus observable output, hosted profile, Call0 only, at
`e866cc16d4fe`. Windowed is a separate and worse story —
[[bug-a-xtensa-windowed-abi-faults-on-frozen-strings-copy-and-dynarray-setlength]].
The 66 compile failures are not covered here; they are missing features rather
than wrong answers, and want their own scoping pass.


---

## UPDATE — 19 of 142, and the handle-leak cluster is closed. frankS, 2026-08-30

**Housekeeping first:** the table above was generated by pasting each program's
raw first line into Markdown, and two of those lines contained non-UTF-8 bytes —
unsurprising for programs that emit garbage, but it made the file undecodable.
Someone else fixed it concurrently with `\xNN` escapes while I was replacing the
bytes with `?`; theirs is kept, because an escape preserves the evidence and a
`?` destroys it. Worth stating for the next person generating a table from raw
output: escape, do not substitute.

`test_cross_var_string_param`'s `varlen=545267744` was the shared ABI predicate
`ABIParamSlotHoldsValueAddr` (abi.inc) being used by x86-64, i386, aarch64,
arm32 and riscv32 — **five of six backends** — while xtensa open-coded only its
by-value-Variant row. Fixed by adopting the predicate; same shape as
[[bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle]] one file
over, and as PXXStrCmp3's "four cross backends" and HeapMmap's seven arms.

Re-swept, same 142 sources: **55 -> 57 matching, 21 -> 19 diverging, zero
regressions.** Newly green: `test_cross_multidim3d` and
`test_cross_param_2darray` — both by-ref ARRAY params, which the predicate also
covers and which nothing in this ticket had connected to the string case. That
is the argument for adopting a shared predicate rather than adding the one row
that was failing.

**Two of the 19 now have their own ticket**, because they share a crisp repro
this ticket's framing hid:
[[bug-a-xtensa-cannot-read-a-managed-string-out-of-a-record-field-or-array-element]].
`WriteLn(r.f)` prints nothing and `Length(r.f)` prints `1936482630` — but so
does `x := r.f; Length(x)`, so the value is wrong before any consumer touches
it. Also a candidate cause for the two interface tests here.

`test_cross_var_string_param` still diverges, on `firstchar` alone: indexing a
managed string through a by-ref parameter (`d[1]`) is still one deref short,
while `Length(d)`, the tail loop and `taillen` are now correct.

---

## WHY XTENSA WAS THE HOLDOUT — and it was not forgetfulness. frankS, 2026-08-30

The coordinator asked for the line that stops a sixth instance, so: traced, not
guessed.

`ABIParamSlotHoldsValueAddr` was created on **2026-08-09** in `d68ff8d16`
("the ABI oracle, slice 1 — the parameter-slot rules"), which converted **five**
backends to it in a single commit: `ir_codegen.inc`, `ir_codegen386.inc`,
`ir_codegen_aarch64.inc`, `ir_codegen_arm32.inc`, `ir_codegen_riscv32.inc`.
`ir_codegen_xtensa.inc` is **not in that commit's file list at all** — and it was
not too new to be: xtensa codegen has existed since `bd49a5953`, 2026-06-12, two
months earlier.

### The sweep's own safety check is what hid it

From `d68ff8d16`'s message:

> *The enforceable invariant is greppable: an `IsRef or` chain inside
> `ir_codegen*.inc` now means someone grew a ninth copy. `grep` finds none.*

That check is sound and it was honestly run. Measured against the parent commit:

| backend | `IsRef or` chains before the sweep |
| --- | --- |
| `ir_codegen.inc`, `386`, `aarch64`, `arm32`, `riscv32` | 1 each |
| **`ir_codegen_xtensa.inc`** | **0** |

Xtensa had zero **not because it was correct, but because it had never
implemented the rule at all.** It open-coded a single row — the by-value
Variant case — spelled `(Syms[si].Kind = skParam) and (Syms[si].TypeKind =
tyVariant)`, which contains no `IsRef` and no `or` chain. So the search found
every backend holding a *wrong duplicate* and could not see the one backend
holding *no copy*, and the file that most needed converting is precisely the one
that satisfied the invariant.

**A search for duplicated logic cannot find the place where the logic is
missing.** That is the exact inverse of this repo's "if you fix a bug on one arm
of a double case, grep for the sibling" rule
([[devdocs/dev/normalise-dont-special-case]]) — grep-for-the-sibling finds
divergent copies, and is blind to absent ones. The generalisation for a sweep
that converts N call sites onto a shared helper: **enumerate the backends that
should call the helper and check each one calls it, rather than searching for
the pattern being replaced.** The first list is closed and countable; the second
is defined by what already exists.

### The second half: the verification list had the same hole

The same commit records: *"verified against FPC on x86-64, aarch64 and arm32
(qemu) plus riscv32."* Four targets, xtensa absent — **because xtensa could not
be executed**, and would not be until the hosted profile landed 2026-08-29/30.

So both of the sweep's safety nets — the static grep and the differential —
excluded xtensa for two unrelated reasons that happened to point the same way.
This is the same sentence as `PXXStrCmp3`'s "four cross backends" and
`HeapMmap`'s seven arms, arriving from a third direction: **the target with no
working oracle is the target that keeps the bug**, and it also keeps the bug
that a conscientious sweep was specifically designed not to leave behind.

Xtensa now runs, and the differential
([[bug-a-hosted-xtensa-diverges-from-the-oracle-on-21-cross-programs]]) is what
found this one.


---

# HANDBACK — the state of hosted xtensa, 2026-08-30 (frankS)

Measured at HEAD `fa01f7111`, compiler `a6b4e6e1816c` (a verified self-host
fixedpoint, sha confirmed different from `pinned`). 129 sources — the union of
what `test-riscv32` and `test-xtensa` compile. **The `142` in this ticket's
title is wrong and cannot be reproduced from the Makefile at any target
combination; treat the partition as N/matching, never as a fixed denominator.**

```
Call0      MATCH 100   DIFF  7   CFAIL 21   (oracle can't build 1)
windowed   MATCH  50   DIFF 55   CFAIL 23
```

*(Updated after the handback: `test_shortstring_trunc` is fixed, and the reason
it was in the DIFF column was not the reason this table originally gave.)*

Call0 over the night: **69 → 99 matching, 21 → 8 diverging**, across nine
changes, **no sweep regressed a program**. Windowed is a different target in
practice and is NOT the subject of any of this — see the windowed ticket.

## The 8 that still diverge, each with an owner

| program | what it is | where it goes |
| --- | --- | --- |
| `test_cross_float_const` | SIGBUS indexing a const array | [[bug-a-a-double-typed-const-misaligns-the-next-const-array-in-the-data-section]] — **read that ticket's correction block first**, its per-target table is invalid |
| `test_cross_float` | ` 3.500000000E+00` vs ` 3.5000000000000000E+000` — exponent digit count and mantissa width | **Track F** (float FORMATTING is F by the 2026-08-19 ruling) — needs a ticket in `float/` |
| `test_cross_trunc_round_saturate` | `Trunc(1e30)` gives `2147483647`, not `9223372036854775807` | **NOT F — needs a bug ticket.** xtensa's `-203/-204` arm calls the **32-bit** `__pxx_d2i` kernel and sign-extends, so Trunc/Round→Int64 is structurally 32-bit. The subject is the conversion mechanism, not float accuracy; rank the mechanism, never the datatype |
| ~~`test_shortstring_trunc`~~ | **FIXED, and my classification of it was wrong.** Not memory corruption — nothing was clobbered. `b` printed `BBBB` with `Length` 4 and the neighbour was intact; `b = 'BBBB'` compared buffer ADDRESSES because the equality guard was gated on `tyAnsiString` only | [[bug-a-a-shortstring-write-on-xtensa-corrupts-a-neighbouring-variable]] — slug kept, premise corrected at the top |
| `test_arm32_record_byval_wide` | `1 7 222 2` and `134730463` where the oracle says `1 7 8 2` and `8` | **needs a bug ticket.** A live address rendered as a decimal number — the exact signature of the `var string` param bug fixed earlier tonight, now on **by-value wide records** |
| `test_cross_syscall` | `0 0 -1` vs `1 1 12345` | needs a ticket; pre-dates the syscall-table work (it was already DIFF in every earlier sweep) |
| `test_rtti` | `InstanceSize: 80` vs `64` | `test-xtensa`'s row filters `InstanceSize:`/pointer lines, as i386/arm32/aarch64 do, so this is excluded there by the same convention — but 80-vs-64 is a real layout difference and deserves its own look |
| `test_asm_ifdef_multiarch` | `0` vs `42` | inline asm under `{$ifdef}` per arch; needs a ticket |

**Three of those eight had no ticket and two were wrong-VALUE bugs.** I named
them here rather than filing them, because a ticket I do not work is worth less
than a row someone reads. One is now fixed — and **the label I put on it was
wrong**: `shortstring_trunc`'s `b-CLOBBERED` was not a clobber at all. I took
the test's own failure message as a diagnosis and repeated it in three places
before anyone had looked at the mechanism. A guard row that names a cause it
does not verify propagates that cause into every summary that quotes it. The
remaining untriaged one is `record_byval_wide`'s address-as-number.

## The 21 that do not compile — seven categories, all named

| n | category | ticket |
| --- | --- | --- |
| 5 | `call0` displacement > ±512 KiB, no veneer | [[bug-a-xtensa-cannot-build-a-program-over-512-kib-of-code-call0-has-no-veneer]] |
| 6 | the scheduler — no `CoSwitch` for xtensa. **Deliberately still red** | [[feature-a-coswitch-for-xtensa-and-riscv32-the-scheduler-has-no-context-switch-there]] |
| 4 | signal: 1 × `IR_SET_SIGNAL` + 3 × SA_SIGINFO, all one missing runtime | [[feature-a-a-signal-runtime-for-HOSTED-xtensa-the-exclusion-predates-the-profile]] |
| 3 | builtins `-55` (needs the entry stub to save the initial sp), `-100`, `-50` | [[feature-a-xtensa-the-last-five-builtins-and-the-entry-stub-that-blocks-one]] — now three, not five |
| 2 | external (dynamic) symbols | **by design** on this target |
| 1 | non-scalar function result (`test_hidden_dynarray_temp_zeroinit`) | needs a ticket |

**Nothing in the tail is unclassified.** That was the point of partitioning it
rather than sampling it: a bucket you have counted is a bucket whose members you
have looked at, and it is what turned "23 assorted failures" into five distinct
filed defects nobody could have named that morning.

## What a green here does and does not mean

Unchanged and still load-bearing: `--xtensa-soft-mulhigh` **labels** the
multiply divergence rather than removing it (no qemu-xtensa core implements
MUL32HIGH), so any arithmetic verdict from this target must name the flag. This
is **Call0 only**. And one row — `test_signal_default_revert_b336` — sits in the
signal family but **installs no handler**: it raises SIGTERM with the default
disposition and dies 143, which needs `kill`, not the signal runtime. It is
coverage-shaped and proves nothing about the family it sits in. I wired it, so
I am flagging it.

## The one methodological thing worth carrying forward

Every fix tonight was a **missing row of a rule the other backends already
carried** — not a novel xtensa problem. `ABIParamSlotHoldsValueAddr`,
`IR_STORE_MEM`'s typed stores, `IR_INDEX`'s managed-string bases, the dyn-array
ops, the set family, `SPECIAL_IN`. The reason they survived is that **a search
for duplicated logic cannot find the place where the logic is missing**: xtensa
passed the "no `IsRef or` chain outside the helper" grep by having no copy at
all. When a sweep converts N call sites onto a shared helper, **enumerate the
backends that should call it and check each one does** — the first list is
closed and countable, the second is defined by what already exists.

---

# RE-MEASURED — 115/5/20 of 140, and only two of the five are compiler bugs. frankA, 2026-08-31

Compiler `db19ff591808` (self-host fixedpoint, `converged after 1 round(s)`,
sha differs from `pinned`). Source list re-derived from the `test-xtensa` and
`test-riscv32` recipes at HEAD.

```
xtensa    MATCH 115   DIFF 5   CFAIL 20     of 140
riscv32   MATCH 127   DIFF 4   CFAIL  8     of 140   (same harness, for contrast)
```

**State the denominator as derived, never as a constant.** 140 is what the two
recipes name today; it was 129 yesterday. The slug's 21 and the body's 142 are
both stale, which is how three numbers in one ticket came to disagree.

## The five, reconciled against how the Makefile actually asserts each row

**Two of them were my sweep, not the compiler.** A source path is not a test
row: the real row also carries flags, an output filter and sometimes a fixed
expected literal, and re-deriving a list from the recipes throws all of that
away. The resulting figure is credible because most rows have no special
handling — which is exactly why it needs reconciling rather than reporting.

| row | verdict |
| --- | --- |
| `test_cross_trunc_round_saturate` | **REAL — FIXED this session**, see below |
| `test_cross_syscall` | **REAL**, `0 0 -1` vs `1 1 12345`. Genuine oracle row (7 Makefile rows across targets), pre-dates the syscall-table work, still unowned |
| `test_cross_float` | **REAL, Track F** — exponent digit count and mantissa width. Float *formatting*, needs a ticket in `float/` |
| `test_asm_ifdef_multiarch` | **TEST GAP, not a compiler bug.** `test/test_asm_ifdef_multiarch.pas` has arms for `CPUX86_64`, `CPURISCV32` and `CPUAARCH64` and **none for xtensa**, so no branch is taken and it prints `0`. Wants an xtensa arm added, not a fix |
| `test_rtti` | **SWEEP ARTIFACT.** The real row (`Makefile:15206-15216`) compiles with `-dPXX_MANAGED_STRING` and filters `pointer:|RTTI value:|InstanceSize:` — the exact lines my sweep reported. The earlier "80 vs 64 is a real layout difference" note reads through the same missing filter |
| `test_signal_altstack` | **SWEEP ARTIFACT** (caught by frankS). `Makefile:15386` wires this for xtensa deliberately and asserts a hardcoded literal containing `code=2`. `code=` is `si_code`: SEGV_MAPERR(1) vs SEGV_ACCERR(2) is a per-arch guard-page reporting difference, also 2 on arm32/aarch64. **The test's real assertion passes on xtensa** — `handler-off-faulting-stack=TRUE`, so sigaltstack works there |

**Do not re-file the last two.** Any sweep that compares them naively to the
x86-64 oracle will rediscover them; that is a property of the comparison, not of
xtensa.

## Fixed: Trunc/Round to Int64 saturated at 2^31 — and it was two targets

xtensa's `-203/-204` arm called the 32-bit `__pxx_d2i`/`__pxx_s2i` and
sign-extended, so every Int64 result past 2^31 came back `2147483647`.
`Trunc(1.0e15)`:

| | single trunc | single round | double trunc |
| --- | --- | --- | --- |
| x86-64 oracle | 999999986991104 | 999999986991104 | 1000000000000000 |
| arm32 | correct | correct | correct |
| **riscv32** | **2147483647** | **2147483647** | correct |
| **xtensa** | **2147483647** | **2147483647** | **2147483647** |

**riscv32's Single arm is the half nobody had reported.** Its double arm was
already on the 64-bit kernel; the single arm beside it was not, and no ticket
named it. Found by varying the operand width while reproducing the xtensa
defect — the "grep for the sibling" rule paying out across targets rather than
within one file.

There is no `__pxx_s2i64`, so the fix promotes to double and uses
`__pxx_d2i64`/`_rne` for both widths — what arm32 already does, and why arm32
was the one correct target. Each backend's two float arms collapse into one.

One trap named at the site: `EmitFloatUnaryCallXtensa`'s `dstDouble` argument
means *the result occupies the a2:a3 pair*, not *the result is a float*. It is
what moves `a11 -> a3` under the windowed ABI, so `False` for a `d2i64` would
drop the Int64's high word — correct under Call0, wrong under windowed.

## The signal cluster: the arms exist AND there is real work behind them

frankS verified the two "no arm" tickets are phantoms but could not say whether
anything real sat behind them. Measured from the other side, there is:

- 3 x `undefined variable (SYS_gettid)` — a missing `lib/rtl` row, not a backend gap
- 1 x the `__pxxSigPCPtr`/`__pxxSigSPPtr` ucontext offsets —
  [[feature-a-xtensa-ucontext-pc-sp-offsets]], the live one
- `test_signal_altstack` **passes its real assertion** (above)

`UContextPCOffset`/`UContextSPOffset` in `ir.inc` claimed "xtensa never reaches
here" and marked both fallthroughs `unreachable`. False: `test_signal_pc_rewrite`
and `test_signal_sp_rewrite` reach them and stop at the `-1` guard with the
intended error. Corrected in the same session (comment-only, binary
byte-identical). frankS's read that those comments are *why* the phantoms still
scan as open looks right.

## Harness note, so the next sweep does not repeat either mistake

1. **Feed the source list on fd 3 and give every child `</dev/null`.** Fed on
   stdin, the test programs inherit the fd and eat the list: my first run
   silently processed **74 of 140** and reported a clean partition, and the
   stdin-reading row "diverged" by printing my own source list back. Assert
   `rows == wc -l < list`; nothing else catches it, because the skipped rows
   produce no output.
2. **Reconcile every non-matching row against its Makefile recipe** before
   reporting it — flags, filters, expected literals. That is what turned 6 into
   3, and it only happened because a peer disputed one row.
