---
slug: bug-c-the-canonical-linux-syscall-asm-idiom-is-refused-output-and-input-may-share-a-fixed-register
title: "the canonical Linux syscall asm idiom is refused: an output and an input may share a fixed register"
track: C
prio: 55
type: bug
status: backlog
created: 2026-09-07
found-by: frank-coord-core
owner: ""
blocked-by: []
summary: "RESOLVED 2026-09-16: a fixed-register OUTPUT met by a fixed-register INPUT on the same register is now TIED rather than refused, so the canonical hand-rolled syscall idiom compiles and runs. used[] recorded only THAT a register was taken, never by what; a parallel usedBy[] separates the legal tie from two inputs colliding and from an operand colliding with a clobber, and those two still error with a message naming the culprit. Exactly one of four gcc-measured shapes changes. Early-clobber is checked AT the tie site, not left to the existing sweep, which runs earlier and reads TiedTo and would have let a '=&a' output tied to an 'a' input through as a silent wrong value."
---

# The canonical syscall idiom does not compile

## Measured 2026-09-07

```c
long f(void) {
  long r;
  __asm__ volatile ("syscall" : "=a"(r) : "a"(158L) : "rcx","r11","memory");
  return r;
}
```

| compiler | result |
| --- | --- |
| gcc | compiles, rc=0 |
| pxx | `pascal26:1: error: C: inline asm wants register constraint "a" but that register is already taken by another operand or a clobber` |

Found by attempting the target, not by triage: this was the probe for
[[bug-a-errno-is-one-global-across-all-threads-so-a-thread-reads-another-threads-failure]],
written to read the FS base with a raw syscall precisely so the measurement
would not import `arch_prctl` from the system C library. The refusal is what
forced the import, and the import is what made the first reading ambiguous.

## Where it is

`cparser.inc:8059-8068`. The loop marks `used[reg]` for every clobber, then
for each operand takes `CAsmFixedReg(Cons)` and errors if `used[fixed]`.
`used[]` records only THAT a register is spoken for, never BY WHAT, so three
different situations collapse into one message:

- an input and an output naming the same register — **legal in gcc, a tie**
- two inputs naming the same register — a real error
- an operand and a clobber naming the same register — a real error

## The shape of the fix, and the trap in it

Outputs occupy indices `0..CAsmOutCount-1` and `opReg[]` is already filled for
them by the time inputs are visited, so an input whose fixed register matches
some output's `opReg[k]` can set `TiedTo := k` and take the same path a `"0"`
constraint takes. The tie machinery already exists (`TiedTo`, resolved at
`cparser.inc:8110`).

**The trap: `"=&a"` output with an `"a"` input must remain an error.**
Early-clobber means the output register is written before the inputs are
consumed, so tying them is exactly the case gcc rejects, and a fix that keys
only on "same register" would accept it and emit code that reads a clobbered
input. `CAsmOps[i].Early` is already recorded. A positive control for this
ticket therefore needs BOTH directions: the `"=a"`/`"a"` pair must compile and
`"=&a"`/`"a"` must still refuse.

## Workaround, so nothing is blocked on this

`"0"` (matching constraint) compiles and runs correctly today and is equally
valid C:

```c
__asm__ volatile ("syscall" : "=a"(r) : "0"(158L) : "rcx","r11","memory");
```

## RESOLVED 2026-09-16 (frankb-56)

`used[]` recorded only THAT a register was spoken for, never BY WHAT, so three
different situations collapsed into one refusal. A parallel `usedBy[]` is the
missing half: `CASM_REG_FREE`, `CASM_REG_CLOBBER`, or an operand index.

A fixed OUTPUT already holding the register, met by a fixed INPUT, is now a
**tie** — `CAsmOps[i].TiedTo` is set to that output and the partner supplies the
register, which is the same route the explicit `"0"` spelling already took.
Everything else still errors, and now says which operand or clobber took it
instead of sending the reader after "another operand or a clobber".

### Not a blanket relaxation — the four rows, measured against gcc, not reasoned about

| shape | gcc | pxx before | pxx after |
| --- | --- | --- | --- |
| `"=a"(r) : "a"(n)` | accepts, runs | refused | **accepts, runs** |
| `"=&a"(r) : "a"(n)` | impossible constraints | refused | refused |
| `"=a"(r) : "a"(n) : "rax"` | impossible constraints | refused | refused |
| `"=r"(r) : "a"(a), "a"(b)` | impossible constraints | refused | refused |

Exactly one row changes. The other three were run through gcc first so the
expected answers came from the built oracle rather than from this ticket's
prediction about them.

**EARLY-CLOBBER IS TESTED AT THE TIE SITE AND NOT LEFT TO THE EXISTING SWEEP,
which is the one thing here that would have silently miscompiled.** The
earlyclobber sweep runs BEFORE this loop and reads `TiedTo`, so a tie minted
here is invisible to it — it would have passed a `"=&a"` output tied to an
`"a"` input straight through. `&` says the output is written before the inputs
are read, so the input's value would be destroyed before the block consumed it:
a wrong VALUE, no diagnostic. Checked explicitly where the tie is made.

### Verified

`test/c_asm_fixed_reg_tie.c`, wired into `test-core`, four rows whose expected
values cannot collide with a default (`0x5eed`, a doubled input, a real syscall
compared against libc's answer to the same question, and the `"0"` spelling
which had to keep working or the fix would have traded a refusal for a
divergence between two spellings of one thing).

    pxx     asm fixed-reg tie: 4 rows OK   rc=0
    gcc     asm fixed-reg tie: 4 rows OK   rc=0
    PINNED  error: inline asm wants register constraint "a" but that register
            is already taken by another operand or a clobber

The pinned compiler is the positive control and refuses with this ticket's own
message, so it is genuinely the unfixed compiler and not passing for an
unrelated reason.

Neighbours re-run because this is shared constraint code: `casm_gnu_operands`
(the busybox `tls_sp_c32.c` arms — matching constraints, `"=rm"`, a fixed `"a"`,
a pinned `"m"`, a `dx` clobber) PASSES; `casm_goto_fails` and
`casm_nonempty_template_fails` still refuse.

Gate: `make compiler/pascal26` converged after 1 round (3f89d5b2fc5d);
`tools/gate.sh quick` GREEN.
