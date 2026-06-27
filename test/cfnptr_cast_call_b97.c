/* Call through a cast-to-function-pointer value: `((RET(*)(params))e)(args)` —
   sqlite's syscall-table idiom `osOpen == ((int(*)(const char*,int,int))
   aSyscall[0].pCurrent)`, used inside an if-condition. The abstract fn-ptr cast
   must register a call signature and the cast node must carry it so the postfix
   `(args)` lowers to an indirect C-ABI call (it previously parsed only outside a
   condition and even there miscompiled the callee). Exit 42. */
struct S { void *p; };
struct S tab[2];
int real_open(const char *z, int a, int b){ return a + b; }
int main(void){
  tab[0].p = (void*)real_open;
  int r = 0;
  if( ((int(*)(const char*,int,int))tab[0].p)("x", 40, 2) > 0 ) r = 1;
  return ((int(*)(const char*,int,int))tab[0].p)("y", 40, 2) + r - 1;
}
