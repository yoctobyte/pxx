/* b236 (bug-c-call-through-deref-of-fnptr-pointer, Track C): a call through a
   DEREF of a POINTER-to-function-pointer obtained by a cast dropped the call.
   CNodeProcSig stripped every AN_DEREF and, for `(**(ft*)pv)(args)`, landed on
   the AN_PTR_CAST whose ASTRight (direct-fnptr-cast sig) is -1, so it returned
   -1 and the trailing `(args)` was dropped — the expression yielded the fn-pointer
   value (code bytes) instead of calling it. This is sqlite os_unix.c's exact
   locking-style finder shape `(**(finder_type*)pVfs->pAppData)(...)`.
   Fix: a cast to a POINTER-to-fn-ptr carries the pointee sig on its alias
   (AliasProcSig); CNodeProcSig keeps one deref as the callee and uses that sig.
   Exit 42 = pass. */
typedef long (*ft)(long);
static long add100(long x) { return x + 100; }
static long neg(long x)    { return -x; }

int main(void) {
    ft f1 = add100, f2 = neg;
    void *pv1 = (void *)&f1;
    void *pv2 = (void *)&f2;

    /* double deref (redundant fn-ptr deref on top of the real load) */
    if ((**(ft *)pv1)(5)  != 105) return 1;
    if ((**(ft *)pv2)(5)  != -5)  return 2;
    /* single deref (one real load) */
    if ((*(ft *)pv1)(7)   != 107) return 3;
    if ((*(ft *)pv2)(7)   != -7)  return 4;
    /* argument marshalling still correct through the indirect call */
    if ((*(ft *)pv1)(-100) != 0)  return 5;
    return 42;
}
