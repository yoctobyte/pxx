# HANDOFF 2026-08-13 — Track A, SA_SIGINFO on the remaining four targets

*A prompt to paste into a fresh session. Written at the end of the session that
landed the x86-64 slice, while the facts were still measured rather than
remembered.*

---

## Paste this

> You are **Track A** (compiler core) on pxx. Confirm you are the only agent on
> Track A before editing shared files.
>
> **Task:** extend `SA_SIGINFO` support from x86-64 to **aarch64, riscv32,
> arm32 and i386**, continuing `feature-signal-siginfo-ucontext`.
>
> **Read first:** `devdocs/progress/backlog/feature-signal-siginfo-ucontext.md`
> — its last two sections are (a) what the x86-64 slice did and why, and (b) a
> per-target survey of exactly what each remaining arch needs, including the
> offsets and the two restorer landmines. It is a checklist; you should not need
> to re-derive any of it.
>
> **Settle this before writing any 32-bit code:** `__pxxSigCode` is typed
> `tyInt64` today. On the ILP32 targets an Int64 is a register PAIR, so either
> those stubs write both words (value + sign word) or the intrinsic is retyped
> to `tyInteger`, which is the field's real width. Retyping is small now and
> breaking later. Decide, state the choice in the ticket, then implement.
>
> **Suggested order** (easiest first, so the risky ones land against a working
> pattern): aarch64 → riscv32 → arm32 → i386.
>
> **Verify each target before moving on:** `tools/run_target.sh <arch>
> /tmp/<bin>` (all four qemu-user binaries are present).
> `test/test_signal_siginfo.pas` is already arch-independent and is the canary
> for both failure modes — its `si_addr` assert against `$DEAD0000` catches a
> wrong union offset, and its `SI_TKILL = -6` half catches a lost sign. Wire a
> per-arch copy into each `test-<arch>` Makefile target, next to the existing
> b371 signal tests.
>
> **Per-fix loop** (do not widen it): `make compiler/pascal26` → your repro →
> `tools/gate.sh quick` → commit → `tools/sync.sh`. Track T sweeps the matrix.

---

## Context you would otherwise have to rediscover

**What landed** (`4636171e0`, gate green, pinned ground is v268 from
`08facb43d`): x86-64 sets `SA_SIGINFO`; the dispatch stub parks
`si_code`/`si_addr`/`ucontext*` in `BSS_SIG_CODE`/`_ADDR`/`_CTX`;
`__pxxSigCode` / `__pxxSigAddr` / `__pxxSigContext` read them. The hook ABI is
unchanged (still a parameterless proc) — that is what made the slice additive,
and it should stay that way for the other targets.

**Cost in the backends was zero and should stay zero.** `AN_SIGINFO` lowers to
`IR_EXC_STORE`, whose `IRC` selects the slot via `IRExcStoreSlot` (extended 2 →
5 slots). All six backends route that op through that one function. If a target
port starts wanting a new IR op, that is a sign of going the wrong way.

**The two landmines, restated** (both from b371, both still armed):
- arm32 and i386 pick the signal FRAME SHAPE by `SA_SIGINFO`, not by which
  syscall installed the handler. Their restorers still call **sigreturn (119)**
  and MUST become **rt_sigreturn (173)** in the same commit that sets the flag,
  or the kernel restores a garbage context (pc=sp=lr=0, instant SIGSEGV).
- i386 additionally must **drop the leading `pop eax`** from its restorer: that
  pop compensates for a stack skew only `sys_sigreturn` has. Both changes or
  neither.

**Why si_code matters at all** — the thing that is expensive to rediscover:
it is the ONLY carrier of *which* fault occurred. The obvious alternative,
reading the MXCSR sticky status flags inside the handler, does not work — Linux
hands the handler a CLEAN FP state, so they read `0x00` whichever exception
trapped. Measured:

```
1.0/0.0     si_code=FLTDIV   mxcsr_flags=0x00
0.0/0.0     si_code=FLTINV   mxcsr_flags=0x00
1e308*10    si_code=FLTOVF   mxcsr_flags=0x00
```

**What this unblocks:** `feature-float-exception-mask-control` (in `blocked/`,
prio 60) is now implementable on x86-64. Its `blocked-by` and its directory are
BOTH set — clearing one alone leaves it invisible to `ready`/`next`. The rest of
item 1 (rewriting the saved RIP in the ucontext so a fault becomes a *catchable*
Pascal raise) is still open and is what
`bug-integer-div-zero-sigfpe-uncatchable` needs.

## Known-bad tooling, so you do not lose time to it

`tools/testmgr.py --pin` **cannot succeed** — it holds the repo lock, spawns the
gate child with `--force`, and the child kills the pid in the lock, which is its
own parent (exit 137, nothing pinned). Filed as
`bug-t-testmgr-pin-force-kills-its-own-parent` (Track T, prio 80, backlog).
Until T fixes it, pin by hand: `make stabilize-fast && make pin`, then commit
`stable_linux_amd64/**`. You only need a pin if you touch `compiler/builtin/**`
— this work does not.
