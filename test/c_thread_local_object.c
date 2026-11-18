/* pxx object: a C __thread in an x86-64 object is real ELF TLS (.tdata.<name>,
   STT_TLS, fs-relative local-exec/initial-exec). Each of four threads must
   see its own copy; the main (gcc) defines tl_ext. With TL_NO_INIT the
   static gets its value from code, for a hosted object, whose initialiser
   would otherwise be an init-thunk store.
   feature-c-thread-local-in-x86-64-objects */
struct pt { int x; long y; };
__thread int tl_count;
#ifdef TL_NO_INIT
static __thread int tl_seed;
#define TL_SEED0 tl_seed = 5
#else
static __thread int tl_seed = 5;
#define TL_SEED0 (void)0
#endif
__thread long tl_arr[4];
__thread struct pt tl_pt;
extern __thread int tl_ext;      /* defined by the gcc main */
static __thread int *tl_self;

int tl_seed_init(void) { TL_SEED0; return 0; }
int tl_work(int k) {
    int i;
    tl_self = &tl_count;
    for (i = 0; i < 1000; i++) { tl_count++; *tl_self += 1; }
    tl_seed += k;
    tl_arr[k & 3] = k * 10;
    tl_pt.x = k; tl_pt.y = (long)k * 100;
    tl_ext += k;
    return tl_count + tl_seed + (int)tl_arr[k & 3] + tl_pt.x + (int)tl_pt.y + tl_ext;
}
int *tl_addr(void) { return &tl_count; }
