/* The definitions c_xtensa_extern_bss_a.c declares extern; a guard word on
   each side of big_buf shows a write through a wrong slot. */
struct proc { int pid; char name[60]; };
int guard0 = 0x55;
struct proc procs[64];
int nprocs;
char big_buf[1000];
int tail;
int guard1 = 0x66;
int guards(void) { return guard0 + guard1; }
