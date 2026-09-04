# Xtensa windowed spill — what is actually available on the hosted profile

Measured 2026-09-04 (frankB, Track A) at origin/master `4b264f3d2`. Written for
[[bug-a-xtensa-windowed-refuses-ir-raise-because-unwind-needs-the-windows-spilled]],
whose banked plan named exactly one unmeasured fact and made one assumption; the
measurement moves both, and in opposite directions from what the plan expected.

Nothing here needs hardware, a cross linker, or a compiler change. The probes are
hand-assembled with `llvm-mc-21 -triple=xtensa` (LLVM 21 has an Xtensa
assembler) and wrapped in a hand-written 84-byte ELF32-LE header, then run under
`qemu-xtensa`. The `xtensa-esp-elf` toolchain on this box is BIG-endian and its
objects will not load under `qemu-xtensa` at all — `Invalid ELF image for this
architecture` — which is why the probes do not use it.

## The three results

| probe | result | meaning |
| --- | --- | --- |
| plain `exit_group(40)` | **rc 40** | the hand-built ELF runs. The harness works. |
| `rsr a5, windowbase` | **rc 132, SIGILL** | reading WINDOWBASE traps in user mode |
| `wsr a4, windowstart` | **rc 132, SIGILL** | ditto, and `rsr` alone is enough to trap |
| `syscall` with `a2 = 0` | **returns, does nothing** | `qemu-xtensa -strace` prints `Unknown syscall 0` |
| 24-deep `call4` chain | **spills** | a caller's `a2` appears in memory |

### 1. The privileged path traps — so newlib's `longjmp` cannot be ported here

The ticket disassembled newlib's windowed `longjmp` and it turns on
`wsr.windowstart` to declare exactly one live window. Under `qemu-xtensa`
linux-user that instruction SIGILLs, and so does the `rsr.windowbase` that
computes its operand. The ticket called this "the one fact that decides whether
the hosted half is a short job or a different design". **It is a different
design.**

### 2. The spill SYSCALL does not exist under qemu — the ticket's cheap path is not there

The plan read newlib's hosted `setjmp` using `syscall` with `a2 = 0` (Linux/xtensa
`spill_registers`) and concluded that on the hosted profile a spill "costs two
instructions". Those two instructions execute and return, so a probe that only
checks for a crash reports success — `-strace` is what shows `Unknown syscall 0`.
On a real Linux/xtensa kernel this call exists; on the only hosted runtime we can
execute, it does not.

### 3. The call-chain spill DOES work — so it is the general case, not the bare-metal fallback

The ticket files the `xthal_window_spill` call-chain trick as the thing bare metal
would need "instead", with the hosted half not waiting on it. Measured the other
way round: a chain of 24 `call4` frames — enough to walk the 64-register file
past a wrap — puts an outer frame's `a2` into memory under qemu, and it uses
nothing but ordinary calls. **It is the one primitive available on every profile
we can run**, and the hosted/bare split the ticket draws does not survive it.

## The two instrument failures on the way, both of which ANSWERED

Worth recording because the first three runs of the spill probe all said "not
found", which would have been banked as "the call-chain spill does not work".

**A dropped literal pool.** `movi a7, 2048` is outside `movi`'s signed 12-bit
range, so `llvm-mc` silently emitted `l32r` — and the probe extracts `.text`
alone, so the literal pool it reads from is not in the image. The loop bound came
from code bytes. The builder below now REFUSES to emit any probe whose
disassembly contains `l32r`.

**Scanning the wrong direction.** The Xtensa ABI reserves the 16 bytes BELOW a
frame's stack pointer for its CALLER's `a0-a3`, so a spilled caller register is
at a NEGATIVE offset from the callee's `a1`. Scanning upward found nothing and
said so.

Neither errored. What caught them was the positive control (`chain_ctl`, which
stores the needle itself and must find it) together with the negative control
(`chain_no`, no spill, which must NOT find it). The pair is what makes a "not
found" mean anything, and with only one of them the probe was wrong twice.

## The harness

`python3 <this script> && qemu-xtensa ./chain_yes; echo $?` — 50 means found,
51 means not found. Requires `llvm-mc-21`, `llvm-objcopy-21`, `qemu-xtensa`.

```python
import struct, subprocess, sys, os
BASE = 0x00400000
HERE = os.path.dirname(os.path.abspath(__file__))
PRE = {
  'chain_no':   '',
  'chain_yes':  '\tmovi\ta6, 24\n\tcall4\tspin\n',
  'chain_sys':  '\tmovi\ta2, 0\n\tsyscall\n',
  'chain_ctl':  '\tmovi\ta8, 1445\n\ts32i\ta8, a1, 100\n',
}
def build(name):
    src = """
	.align	4
_start:
	call4	f1
	movi	a2, 119
	movi	a6, 60
	syscall
	.align	4
f1:
	entry	a1, 48
	movi	a2, 1445
	call4	f2
	movi	a2, 119
	movi	a6, 61
	syscall
	.align	4
spin:
	entry	a1, 32
	beqz	a2, .Lsret
	addi	a2, a2, -1
	mov	a6, a2
	call4	spin
.Lsret:
	retw
	.align	4
f2:
	entry	a1, 48
""" + PRE[name] + """
	movi	a3, -512
	movi	a4, 1445
	movi	a5, 51
	movi	a7, 256
.Lloop:
	add	a8, a1, a3
	l32i	a8, a8, 0
	bne	a8, a4, .Lnext
	movi	a5, 50
	j	.Ldone
.Lnext:
	addi	a3, a3, 4
	addi	a7, a7, -1
	bnez	a7, .Lloop
.Ldone:
	mov	a6, a5
	movi	a2, 119
	syscall
"""
    p = subprocess.run(['llvm-mc-21','-triple=xtensa',
                        '-mattr=+exception,+windowed,+density',
                        '-filetype=obj','-o','/dev/stdout'],
                       input=src.encode(), capture_output=True)
    if p.returncode: sys.exit('llvm-mc: '+p.stderr.decode())
    open('/tmp/c.o','wb').write(p.stdout)
    q = subprocess.run(['llvm-objcopy-21','-O','binary','--only-section=.text',
                        '/tmp/c.o','/tmp/c.bin'], capture_output=True)
    if q.returncode: sys.exit('objcopy: '+q.stderr.decode())
    code = open('/tmp/c.bin','rb').read()
    dis = subprocess.run(['llvm-objdump-21','-d',
                          '--mattr=+exception,+windowed,+density','/tmp/c.o'],
                         capture_output=True).stdout.decode()
    if 'l32r' in dis:
        sys.exit('REFUSING ' + name + ': llvm-mc emitted l32r, and '
                 '--only-section=.text drops the literal pool it reads from. '
                 'The probe would answer from code bytes.')
    ehsz, phsz = 52, 32; off = ehsz + phsz
    eh = b'\x7fELF' + bytes([1,1,1,0]) + b'\0'*8
    eh += struct.pack('<HHIIIIIHHHHHH', 2, 94, 1, BASE+off, ehsz, 0, 0x100,
                      ehsz, phsz, 1, 40, 0, 0)
    ph = struct.pack('<IIIIIIII', 1, 0, BASE, BASE, off+len(code),
                     off+len(code), 5, 0x1000)
    path = os.path.join(HERE, name)
    open(path,'wb').write(eh+ph+code); os.chmod(path,0o755)
    print('built', name)
for n in PRE: build(n)
```


---

# A windowed longjmp that uses no privileged instruction — MEASURED, rc 50

Measured 2026-09-04 (frankB, Track A), same harness, same box. The section above
established that the call-chain spill is the only spill primitive available to
us. **This one establishes that it is enough**: the whole transfer works, in the
shape the backend actually emits, with no `rsr`, no `wsr` and no syscall.

Builder: `devdocs/dev/xtensa-windowed-longjmp-probe.py`
(`python3 <it> && qemu-xtensa ./lj8_yes; echo $?`).

| probe | rc | meaning |
| --- | --- | --- |
| `lj8_yes` | **50** | control transferred from 20 frames deep back into `f1`, BOTH needles intact, the setjmp call returned 1 |
| `lj8_nospill` | 52 | same code with the spill removed: the transfer happens and the needle is WRONG |
| `lj_yes` / `lj_nospill` | 50 / 52 | the call4 shape, same result |

`lj8_nospill` is the negative control and it matters: without the spill the outer
windows are still live in the register file, so `retw` finds the target window
valid, never underflows, and the memory we wrote is ignored. It still *lands* —
which is why "did it crash" would have been the wrong question — and it lands
with stale registers.

## The protocol

`F` is the try site: a `call8` frame, so it owns `a0-a7`. Both stubs are entered
from `F` by `call8`, which is what makes the register arithmetic line up — the
forged call-size bits in `a0` must equal the size of the call being unwound to,
and `longjmp`'s own `a2` must land where `setjmp`'s did.

**setjmp(buf)** — `entry a1, N`, then:

1. spill: `movi a10, 16` / `call8 spin`, `spin` being a self-recursive `call8`
   chain deep enough to walk the register file past a wrap
2. `buf[0..15] := [setjmp_sp - 16]` — **F's `a0-a3`**. `[callee_sp - 16]` holds
   the CALLER's `a0-a3`, measured, not assumed
3. `F_sp := [setjmp_sp - 12]` (F's own `a1`, from that same block);
   `cs := [F_sp - 12]` (F's caller's `a1`)
4. `buf[40] := cs`; `buf[16..31] := [cs - 32 .. cs - 17]` — **F's `a4-a7`**
5. `buf[32] := a0` (return address WITH its call-size bits), `buf[36] := a1`
6. return 0

**longjmp(buf)** — `entry a1, N`, then:

1. spill (this is what makes every outer window dead and in memory, so the
   `retw` below underflows from the bytes we are about to write)
2. `[buf[36] - 16 ..] := buf[0..15]`
3. `[buf[40] - 32 ..] := buf[16..31]`
4. `a0 := buf[32]` ; `a2 := 1` ; `a1 := buf[36]` ; `retw`

`retw` decrements the window base by the forged call size and the underflow
handler reloads the target frame from the two blocks just written. Control lands
at `buf[32] & $3FFFFFFF`, inside `F`, with `F`'s registers restored and `1`
visible where the call's result goes.

## The two save areas are in DIFFERENT PLACES and only one of them is volatile

This is the part that cost the measurements, and reasoning produced the wrong
answer three times.

- **`a0-a3` at `[callee_sp - 16]`** — inside the callee region, so by the time a
  raise happens it holds some deeper frame's registers. This is why `setjmp` must
  copy it out and `longjmp` must put it back: the transfer pretends the stack is
  as it was at `setjmp` time.
- **`a4-a7` at `[cs - 32]`**, `cs` being **F's caller's** stack pointer — inside
  F's OWN frame, and therefore stable across everything F calls.

`[F_sp - 32]`, `[cs - 16]` and `[cs - 20]` were all tried first and all wrong.

**And a scan for the spilled value finds copies in BOTH directions, of which
only the upward one is the answer.** Scanning up from `F_sp - 256` reports a hit
at `F_sp - 160`; scanning DOWN from `F_sp` reports the same address. Both are
real bytes and both are the wrong answer — that address moves when the *spill
chain's* frame size changes (32 -> 48 moved it to `F_sp - 192`), which is the
tell that it is an artifact of the chain rather than an ABI location. The copy at
`[cs - 32]` does not move for either stub's frame size and moves exactly with
F's own, which is what an ABI location does. **A probe that finds a plausible
value and stops is the failure mode here; varying the geometry is what separates
the two.**

## What this leaves for the implementation

The banked plan's remaining items are now moot. No `rsr`/`wsr` encoders, no
`extui`, no privileged access, no syscall: `xtensa_entry`, `xtensa_retw`,
`xtensa_call8`, `xtensa_l32i`, `xtensa_s32i`, `xtensa_addi` and `xtensa_movi`
already exist in `compiler/xtensaenc.inc` and are the whole instruction set this
needs. The jmpbuf grows from 3 words (Call0: a15, sp, a0) to 11.


## The root window is not an ordinary frame, and it is the one `main` runs in

Found 2026-09-04, immediately after the compiler change landed, by a `try` in
the MAIN PROGRAM BODY: it SIGSEGV'd while the identical `try` one procedure
down worked.

Every frame's 16-byte block at `[sp-16]` is written **by its caller** — the
window overflow handler puts the caller's `a0-a3` there. Every frame gets one
for free except one: the process entry reaches its frame through a bare `entry`
from the ROOT window and was never `CALL8`'d, so nothing ever fills the block
below it. The word at `[sp-12]`, which `setjmp` reads to find the frame's
caller, is whatever the kernel left on the stack. The walk then dereferences it.

Harmless until something walks the chain, which is why it surfaced only when
the windowed unwind landed and not before.

| probe | rc |
| --- | --- |
| `lj8root_yes` — the try frame entered from the root window by a bare `entry` | **139** |
| `lj8seed_yes` — the same, with four stores seeding the frame's own save area | **50** |

The fix is those four stores, emitted right after the outermost `entry`
(`ir_codegen.inc`, the windowed startup): `a0`, the **pre-`entry` sp**, `a2`,
`a3` into `[sp-16..sp-1]`. The pre-`entry` sp is the honest value for `[sp-12]`:
it is where this frame's caller's stack pointer would be if it had one, and it
makes `[that - 32]` — the extended save area — land inside this frame, which is
mapped and owned.

**Reproduced outside the compiler before the compiler was touched**, which is
the point of keeping the builder: the first hypothesis was that the PROC CLEANUP
frame was at fault (it had just been enabled for windowed in the same commit),
and closing that predicate again changed nothing. The 30-instruction probe named
the real frame in one run.
