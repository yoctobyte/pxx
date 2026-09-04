import struct, subprocess, sys, os
BASE = 0x00400000
HERE = os.path.dirname(os.path.abspath(__file__))

# The same transfer in the shape the pxx backend actually emits: CALL8.
# f1 is a call8 frame, so it owns a0-a7 and a spill puts a0-a3 at [f1_sp-16]
# (volatile -- it is inside the callee region) and a4-a7 at [f1_caller_sp-32]
# (stable -- it is inside f1's own frame). Both are saved and both restored,
# which is what newlib does and what makes the restore independent of whether
# the prologue reserves the extended area.
#
# jmpbuf: +0 f1's a0-a3 | +16 f1's a4-a7 | +32 setj's a0 | +36 setj's a1
#         +40 f1's caller sp
#
# 50 = landed in f1, BOTH needles intact, setj returned 1
# 52 = a3 needle wrong   54 = a5 needle wrong (extended area)   53 = bad retval
# 60 = f1 returned normally, no transfer
SRC = r"""
	.align	4
_start:
	call8	f1
	movi	a2, 119
	movi	a6, 61
	syscall

	.align	4
f1:
	entry	a1, 64
	movi	a3, 1445
	movi	a5, 1789
	addi	a10, a1, 16
	call8	setj
	beqz	a10, .Lfirst
	movi	a11, 1
	bne	a10, a11, .Lbadret
	movi	a11, 1445
	bne	a3, a11, .Lbadneedle
	movi	a11, 1789
	bne	a5, a11, .Lbadext
	movi	a2, 119
	movi	a6, 50
	syscall
.Lbadneedle:
	movi	a2, 119
	movi	a6, 52
	syscall
.Lbadext:
	movi	a2, 119
	movi	a6, 54
	syscall
.Lbadret:
	movi	a2, 119
	movi	a6, 53
	syscall
.Lfirst:
	addi	a10, a1, 16
	movi	a11, 20
	call8	deep
	movi	a2, 119
	movi	a6, 60
	syscall

	.align	4
deep:
	entry	a1, 48
	beqz	a3, .Lbottom
	addi	a3, a3, -1
	mov	a10, a2
	mov	a11, a3
	call8	deep
	retw
.Lbottom:
	mov	a10, a2
	call8	longj
	retw

	.align	4
spin:
	entry	a1, 32
	beqz	a2, .Lsret
	addi	a2, a2, -1
	mov	a10, a2
	call8	spin
.Lsret:
	retw

	.align	4
setj:
	entry	a1, 32
	movi	a10, 16
	call8	spin
	addi	a8, a1, -16
	l32i	a9, a8, 0
	s32i	a9, a2, 0
	l32i	a9, a8, 4
	s32i	a9, a2, 4
	l32i	a9, a8, 8
	s32i	a9, a2, 8
	l32i	a9, a8, 12
	s32i	a9, a2, 12
	addi	a8, a1, -16
	l32i	a8, a8, 4
	addi	a8, a8, -16
	l32i	a8, a8, 4
	s32i	a8, a2, 40
	addi	a8, a8, -32
	l32i	a9, a8, 0
	s32i	a9, a2, 16
	l32i	a9, a8, 4
	s32i	a9, a2, 20
	l32i	a9, a8, 8
	s32i	a9, a2, 24
	l32i	a9, a8, 12
	s32i	a9, a2, 28
	s32i	a0, a2, 32
	s32i	a1, a2, 36
	movi	a2, 0
	retw

	.align	4
longj:
	entry	a1, 32
	movi	a10, 16
	call8	spin
	l32i	a7, a2, 36
	addi	a8, a7, -16
	l32i	a9, a2, 0
	s32i	a9, a8, 0
	l32i	a9, a2, 4
	s32i	a9, a8, 4
	l32i	a9, a2, 8
	s32i	a9, a8, 8
	l32i	a9, a2, 12
	s32i	a9, a8, 12
	l32i	a8, a2, 40
	addi	a8, a8, -32
	l32i	a9, a2, 16
	s32i	a9, a8, 0
	l32i	a9, a2, 20
	s32i	a9, a8, 4
	l32i	a9, a2, 24
	s32i	a9, a8, 8
	l32i	a9, a2, 28
	s32i	a9, a8, 12
	l32i	a0, a2, 32
	movi	a2, 1
	mov	a1, a7
	retw
"""

def build(name, src):
    p = subprocess.run(['llvm-mc-21','-triple=xtensa',
                        '-mattr=+exception,+windowed,+density',
                        '-filetype=obj','-o','/dev/stdout'],
                       input=src.encode(), capture_output=True)
    if p.returncode: sys.exit('llvm-mc: '+p.stderr.decode())
    open('/tmp/lj8.o','wb').write(p.stdout)
    q = subprocess.run(['llvm-objcopy-21','-O','binary','--only-section=.text',
                        '/tmp/lj8.o','/tmp/lj8.bin'], capture_output=True)
    if q.returncode: sys.exit('objcopy: '+q.stderr.decode())
    code = open('/tmp/lj8.bin','rb').read()
    dis = subprocess.run(['llvm-objdump-21','-d',
                          '--mattr=+exception,+windowed,+density','/tmp/lj8.o'],
                         capture_output=True).stdout.decode()
    if 'l32r' in dis:
        sys.exit('REFUSING '+name+': llvm-mc emitted l32r.')
    ehsz, phsz = 52, 32; off = ehsz + phsz
    eh = b'\x7fELF' + bytes([1,1,1,0]) + b'\0'*8
    eh += struct.pack('<HHIIIIIHHHHHH', 2, 94, 1, BASE+off, ehsz, 0, 0x100,
                      ehsz, phsz, 1, 40, 0, 0)
    ph = struct.pack('<IIIIIIII', 1, 0, BASE, BASE, off+len(code),
                     off+len(code), 5, 0x1000)
    path = os.path.join(HERE, name)
    open(path,'wb').write(eh+ph+code); os.chmod(path,0o755)
    print('built', name, len(code), 'bytes')

build('lj8_yes', SRC)

# ---- THE ROOT WINDOW IS NOT AN ORDINARY FRAME, and it is the one the pxx main
# body runs in. Every frame gets the 16-byte block below its stack pointer
# written by its CALLER -- except the process entry, which reaches its frame
# through a bare `entry` from the root window and was never CALL8'd. So
# [F_sp-12], which setjmp reads to find the frame's caller, is whatever the
# kernel left there, and the walk faults.
#
# lj8root_yes reproduces it in 30 instructions (rc 139). lj8seed_yes is the fix
# -- four stores seeding the frame's own save area right after `entry`, with
# the pre-entry sp as the caller pointer -- and returns 50. That is the change
# ir_codegen.inc's windowed startup now makes.
ROOT = SRC.replace("""\t.align\t4
_start:
\tcall8\tf1
\tmovi\ta2, 119
\tmovi\ta6, 61
\tsyscall

\t.align\t4
f1:
\tentry\ta1, 64""", """\t.align\t4
_start:
\tj\tf1

\t.align\t4
f1:
\tentry\ta1, 288""")
assert ROOT != SRC, 'root-frame anchor'
build('lj8root_yes', ROOT)

SEED = ROOT.replace("""\tentry\ta1, 288
\tmovi\ta3, 1445""", """\tentry\ta1, 288
\tmovi\ta9, 288
\tadd\ta9, a1, a9
\taddi\ta8, a1, -16
\ts32i\ta0, a8, 0
\ts32i\ta9, a8, 4
\ts32i\ta2, a8, 8
\ts32i\ta3, a8, 12
\tmovi\ta3, 1445""")
assert SEED != ROOT, 'seed anchor'
build('lj8seed_yes', SEED)
build('lj8_nospill', SRC.replace("""	entry	a1, 32
	movi	a10, 16
	call8	spin
	l32i	a7, a2, 36""", """	entry	a1, 32
	l32i	a7, a2, 36"""))
