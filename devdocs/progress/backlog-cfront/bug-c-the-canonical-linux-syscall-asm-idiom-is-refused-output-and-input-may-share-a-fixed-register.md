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
summary: "gcc accepts `__asm__(\"syscall\" : \"=a\"(r) : \"a\"(158L) : \"rcx\",\"r11\",\"memory\")` and pxx refuses it with `C: inline asm wants register constraint \"a\" but that register is already taken by another operand or a clobber` (cparser.inc:8064). That is the shape of every hand-rolled syscall wrapper -- musl, the kernel's own headers, and anything that talks to the kernel without libc -- so it is code someone MEANT to write, which makes it compat and not a rejected divergence. gcc's rule is that a fixed-register OUTPUT and a fixed-register INPUT naming the same register are TIED, exactly as if the input had used a matching constraint; pxx's used[] check cannot tell that legal pairing from two inputs colliding, or from an operand colliding with a clobber, and refuses all three. The `\"0\"` matching-constraint spelling compiles and runs correctly today, so this is a diagnostic-shaped refusal with a workaround, not a miscompile. NOT a blanket relaxation: an EARLY-CLOBBER output (`\"=&a\"`) paired with an `\"a\"` input must STAY an error, because early-clobber means the output is written before the inputs are consumed -- that is the distinction the fix has to carry and it is why this is not a two-line change."
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
