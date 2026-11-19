/* x86-64 encodings the GNU as frontend must produce BYTE-IDENTICAL to gas
   (tools/check_gas_frontend.sh, check 5). NetBSD's x86-64 libc/libkern .S
   sources (rump): test with an immediate, imul's 1- and 3-operand forms,
   movz/movs with both widths in the mnemonic, %ah/%ch/%dh/%bh by name,
   shld/shrd, and 64-bit immediates (memset.S's mov $0x0101010101010101 was
   truncated to 32 bits). Left out on purpose, as valid but differently
   encoded: xchgb %ah,%al (operands swapped in ModRM), shrb $1 (gas: D0),
   and a byte ALU immediate on %dl (pxx adds a redundant REX).
   feature-gas-netbsd-libc-string-and-atomic-sources
   bug-gas-a-64-bit-immediate-was-truncated-to-32-bits */
        .text
        .globl gas_enc
gas_enc:
 testb $7,%sil
 test $7,%dil
 test $7,%dl
 testl $0x80,(%rdi)
 testq $0x100,%rax
 testw $0x1234,%cx
 testb $1,(%rax,%rdi,2)
 testq %r9,%rdx
 testb %dl,(%rax,%rdi)
 test (%rax),%dl
 imul $0x80,%r8,%r9
 imul $5,%rax
 imul $100000,%rsi,%r12
 imulw $-3,%cx,%dx
 imul %r9,%rax
 imull %ecx
 imulq (%rdi)
 imull 8(%rsp)
 movb %cl,%ch
 movb %bh,(%rdi)
 movzbq %sil,%rsi
 movzbq %dil,%rdx
 movzbl %al,%eax
 movzbl %ah,%eax
 movzbw %r9b,%r10w
 movzwl (%rdi),%eax
 movzwq 2(%rdi,%rcx,2),%r11
 movsbq %dl,%rax
 movsbl (%rsi),%ecx
 movswq %r8w,%rax
 movslq %edx,%rax
 movslq (%rdi),%r15
 testb $5,%al
 testw $5,%ax
 testl $5,%eax
 shld $1,%eax,%edx
 shrdq $7,%r9,%rax
 shld %cl,%rsi,(%rdi)
 shrd %eax,%edx
 shldw $3,%ax,%bx
        mov $0x0101010101010101,%r9
        movq $0x8080808080808080,%rax
        mov $-1,%rax
        mov $0x80000000,%rax
        mov $0xffffffff,%rax
        movq $0x7fffffff,%rcx
        andb $7,%ah
        subb $1,%ch
        cmpb $3,%bh
        orb $1,%ah
        sarb %cl,%ah
        # SMAP around a kernel's user-memory access (Rainyday ticket 0024)
        stac
        clac
        ret
