/* Extern declarations take no .bss in a freestanding ESP object
   (ObjBssPlan): live globals interleaved with extern ones must keep distinct,
   aligned slots after the dead ranges are cut, from code AND from data
   (pointer initialisers). The externs live in c_xtensa_extern_bss_b.c.
   Run under qemu-xtensa by tools/check_xtensa_freestanding_struct.py;
   check() & 255 == 189 (gcc's value), and
   the object's .bss is under 256 bytes. bug-c-extern-declarations-get-bss-in-every-object */
struct proc { int pid; char name[60]; };
char c1;
extern struct proc procs[64];
long long ll;
extern int nprocs;
static short sh;
extern char big_buf[1000];
int live[5];
double d;
extern int tail;
extern int guards(void);
int *plive = &live[2];
char *pc1 = &c1;
long long *pll = &ll;
int check(void) {
    int i, s = 0;
    c1 = 3; ll = 0x100000007LL; sh = 11; d = 2.0;
    for (i = 0; i < 5; i++) live[i] = i * 10;
    procs[3].pid = 17; nprocs = 4; big_buf[999] = 5; tail = 9;
    if (((unsigned)&ll & 7) != 0) return 1;
    if (((unsigned)&d & 7) != 0) return 2;
    s += c1 + (int)(ll >> 32) + (int)(ll & 0xff) + sh + (int)d;   
    s += *plive + *pc1 + (int)*pll;                               
    for (i = 0; i < 5; i++) s += live[i];                          
    s += procs[3].pid + nprocs + big_buf[999] + tail;              
    s += guards() - 0xbb;                                          /* the guard words intact */
    return s;
}
