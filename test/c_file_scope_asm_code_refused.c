/* File-scope asm holding CODE: it was dropped silently, then refused by name
   (feature-c-file-scope-asm-symbol-aliases), and is assembled since
   8d21004d32 -- myfunc is a defined function, alias2 stays a weak alias
   (rump repro s03). The file keeps its old name; the row checks the
   symbols. feature-c-file-scope-asm-that-defines-code */
__asm(".globl myfunc\nmyfunc:\n movl $42,%eax\n ret\n");
int myfunc(void);
int real(void) { return 1; }
__asm(".weak alias2\n.set alias2, real");
int f(void) { return myfunc(); }
