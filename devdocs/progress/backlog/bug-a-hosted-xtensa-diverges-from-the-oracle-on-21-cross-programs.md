---
track: A+S
type: bug
prio: 40
status: open
found: 2026-08-30
found-by: frankS
---

# Hosted xtensa diverges from the x86-64 oracle on 21 of 142 cross programs

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
