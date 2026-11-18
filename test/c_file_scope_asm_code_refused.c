/* File-scope asm holding CODE is refused by name (it was dropped silently).
   feature-c-file-scope-asm-symbol-aliases */
__asm(".globl myfunc\nmyfunc:\n movl $42,%eax\n ret\n");
int myfunc(void);
int real(void) { return 1; }
__asm(".weak alias2\n.set alias2, real");
int f(void) { return myfunc(); }
