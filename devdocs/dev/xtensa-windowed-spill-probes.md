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
