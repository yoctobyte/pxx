/* The C-side half of test_external_proc_addr_callable.pas: a bare imported C
   function name must decay to the address the CALL path would use -- not merely
   to a non-nil one.

   THE EXISTING C TEST PROVES LESS THAN ITS NAME SAYS, in two ways, and the
   second is the one that made this file necessary.  cexternal_func_addr_b106.c
   takes `(puts_fn)puts` and asserts `f == 0 ? 1 : 42`.  It (a) never calls
   through the pointer, so a wrong-but-mapped address passes it -- frankA
   measured exactly that on the Pascal side, where a deliberately +8-shifted
   addend resolved `@strlen` to the neighbouring GOT entry, returned 12 instead
   of 11, exit code 0, no crash, every nil check green.  And (b), measured here
   before writing this file: `puts` is DEFINED BY CRTL, so that object has no
   dynamic section at all -- `readelf -d` reports "There is no dynamic section in
   this file".  It never reaches RegisterExternal, a GOT slot,
   EmitExternalProcAddr or PatchDynCallSites.  Adding a call-through to it would
   still have proved nothing: the population is empty, not merely under-checked.

   So the two externals below are chosen for the one property that makes this a
   real subject -- crtl does NOT define them, which is what earns a GOT slot and
   a DT_NEEDED.  That is also why the build prints "crtl does not define"
   warnings and why --system-libs=c is passed: here the system import IS the
   thing under test, not an accident (CWarnImplicitSystemImports, cparser.inc).
   If a future crtl grows strcasecmp or strncasecmp this file goes silently back
   to proving nothing; the tell is `readelf -d` losing its NEEDED entry, and the
   fix is to pick another name crtl lacks, not to delete the test.

   THE PAIR IS DELIBERATE, AND SO IS THE ORDER OF THE CHECKS.  Measured: the two
   land in ADJACENT GOT slots (0x...5c8 and 0x...5d0) while a third external
   sits past a gap, so these two are what a one-slot error actually swaps.  They
   also disagree on the same inputs -- strncasecmp("abc","abd",2) is 0 where
   strcasecmp("abc","abd") is negative -- so a swap is visible in BOTH
   directions rather than only one.  With a single external the neighbouring
   slot is zero and the bug degrades into the easy nil case that the old test
   already caught.

   POSITIVE CONTROL, run before committing: `slotVA := slotVA + 8` injected into
   PatchDynCallSites (elfwriter.inc).  This file exits 4 -- the VALUE check --
   with @strcasecmp resolved to strncasecmp's real mapped address: no crash, no
   nil, clean exit.  cexternal_func_addr_b106.c still exits 42 on the same
   binary.  A -8 injection segfaults instead, which is the easy case everything
   catches.  The value comparison is therefore the only guard here that rejects
   the interesting defect, and it has been shown to reject it.

   WHAT IT FOUND ON ITS FIRST RUN, which is not what it was written for: the
   value comparison failed on a CLEAN compiler, x86-64 and aarch64 both.  The
   GOT address was right; the RETURN was not.  SysV defines only EAX for a
   32-bit `int` return and AAPCS64 only W0, so the upper half of the accumulator
   is undefined -- and the value model treats every result as full 64-bit.  The
   DIRECT x86-64 call path already widened with `cdqe`
   (bug-c-crtl-pulled-fn-inline-signed-compare); its indirect sibling did not,
   and the aarch64 backend did neither.  A negative return used INLINE, as in
   `if f("abc","abd") != dl`, compared a raw accumulator against a movslq'd
   local and took the wrong branch -- silently, no crash.  Storing it to an int
   first hid it, because the tyInt32 load sign-extends.  arm32/i386/riscv32 are
   32-bit and have no upper half to be undefined; measured, not assumed.
   That is why the test asserts a NEGATIVE result and a zero one: with only
   `strcasecmp("Hello","hello")` it would have passed on every target.

   feature-a-x86-64-object-output-is-position-dependent */
int strcasecmp(const char *a, const char *b);
int strncasecmp(const char *a, const char *b, unsigned long n);

typedef int (*cmp_fn)(const char *, const char *);
typedef int (*ncmp_fn)(const char *, const char *, unsigned long);

int main(void) {
  cmp_fn f;
  ncmp_fn g;
  int direct_lt, direct_eq;

  f = (cmp_fn)strcasecmp;
  if (f == 0) return 1;

  /* Known-true values first, so "both paths wrong the same way" cannot pass by
     agreeing with each other. */
  direct_lt = strcasecmp("abc", "abd");
  direct_eq = strcasecmp("Hello", "hello");
  if (direct_lt >= 0) return 2;
  if (direct_eq != 0) return 3;

  /* The check the control fires on. Before g's nil test on purpose: a one-slot
     error makes THIS the failure, and a nil test placed ahead of it would
     report the same defect less precisely. */
  if (f("abc", "abd") != direct_lt) return 4;
  if (f("Hello", "hello") != direct_eq) return 5;

  g = (ncmp_fn)strncasecmp;
  if (g == 0) return 6;
  if ((void *)g == (void *)f) return 7;
  /* 0 where strcasecmp is negative -- the reverse direction of the swap. */
  if (strncasecmp("abc", "abd", 2) != 0) return 8;
  if (g("abc", "abd", 2) != 0) return 9;
  if (g("abc", "abd", 3) >= 0) return 10;

  return 42;
}
