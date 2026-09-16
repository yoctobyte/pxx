/* A fixed-register OUTPUT and a fixed-register INPUT naming one register are
   TIED, not a collision — gcc's rule, and the shape of every hand-rolled
   syscall wrapper (musl, the kernel's own headers, anything that talks to the
   kernel without libc).
   bug-c-the-canonical-linux-syscall-asm-idiom-is-refused-output-and-input-may-share-a-fixed-register

   THIS FILE IS THE HALF THAT MUST COMPILE. The three shapes that must STAY
   REFUSED cannot live here — the harness has no "must not compile" form — so
   they are recorded in the ticket with the gcc measurement that fixes each
   expected answer. All four were measured against gcc rather than reasoned
   about, because the refusals are the part a relaxation quietly takes with it:

     "=a"(r) : "a"(n)            gcc accepts, runs      <- this file
     "=&a"(r) : "a"(n)           gcc: impossible constraints
     "=a"(r) : "a"(n) : "rax"    gcc: impossible constraints
     "=r"(r) : "a"(a), "a"(b)    gcc: impossible constraints

   THE VALUES CANNOT PASS BY COLLISION. Each row returns something that is not
   0, not 1 and not the register's incoming content: 0x5eed, a doubled input,
   and a real syscall result compared against the libc answer for the same
   question. A row that merely "ran" cannot score here. */
#include <stdio.h>
#include <unistd.h>

/* (1) the bare tie: the output register is also the input register.
   `nop` rather than an empty template — pxx refuses an empty template that
   has an output, on the ground that it cannot have written one, which is a
   separate and correct limitation this file must not trip over. */
static long thru(long n) {
  long r;
  __asm__ volatile ("nop" : "=a"(r) : "a"(n) : "memory");
  return r;
}

/* (2) the tie is not a no-op — the block must really run with the input in
   place. `add %%rax,%%rax` doubles it, so a stale or zero rax is visible. */
static long dbl(long n) {
  long r;
  __asm__ volatile ("add %%rax,%%rax" : "=a"(r) : "a"(n) : "cc");
  return r;
}

/* (3) the real idiom, which is why the ticket exists: a raw syscall with no
   libc import at all. getpid is 39 on x86-64. Checked against libc's own
   getpid() so the row asserts a RELATION and carries no expected number. */
static long sys_getpid(void) {
  long r;
  __asm__ volatile ("syscall" : "=a"(r) : "a"(39L) : "rcx", "r11", "memory");
  return r;
}

/* (4) the explicit "0" matching-constraint spelling, which compiled before this
   fix and must still compile: the two spellings have to agree, or the fix
   traded one refusal for a divergence. */
static long thru_matching(long n) {
  long r;
  __asm__ volatile ("nop" : "=a"(r) : "0"(n) : "memory");
  return r;
}

int main(void) {
  int fails = 0;
  long v;

  v = thru(0x5eed);
  if (v != 0x5eed) { printf("FAIL tie: %ld\n", v); fails++; }

  v = dbl(0x5eed);
  if (v != 0x5eed * 2) { printf("FAIL dbl: %ld\n", v); fails++; }

  v = sys_getpid();
  if (v != (long)getpid()) { printf("FAIL syscall: %ld vs %ld\n", v, (long)getpid()); fails++; }

  v = thru_matching(0x5eed);
  if (v != 0x5eed) { printf("FAIL matching: %ld\n", v); fails++; }

  if (!fails) printf("asm fixed-reg tie: 4 rows OK\n");
  return fails != 0;
}
