/* asm labels (int foo(int) __asm("bar"), NetBSD __RENAME; `long v asm("sym");`,
   kern_tc.c) and file-scope aliases the same file also calls/reads (locks.c,
   vm.c). Linked under c_asm_label_main.c. feature-c-asm-labels-rename-the-symbol */
int foo(int) __asm("bar");
int foo(int x) { return x + 1; }
int callfoo(void) { return foo(2); }

int ext(int) __asm("real_ext");
int callext(void) { return ext(3); }

long time_second_legacy asm("time_second");
void set_second(long s) { time_second_legacy = s; }

void mutex_exit(int *m) { *m = 0; }
void mutex_spin_exit(int *m);
__asm(".weak mutex_spin_exit\nmutex_spin_exit = mutex_exit");
int use_spin(void) { int m = 9; mutex_spin_exit(&m); return m; }

int vnodeops_real = 17;
extern int vnodeops;
__asm(".global vnodeops\nvnodeops = vnodeops_real");
int read_ops(void) { return vnodeops + 1; }
