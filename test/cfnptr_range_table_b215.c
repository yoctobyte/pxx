/* Regression: file-scope fn-pointer array with `[k]=` designators AND GNU range
   `[lo ... hi]=` — the c-testsuite 00216 syscall/reloc-table shape. The fn-ptr
   global array scanner now tracks a per-element target index (arrTgt[]) and
   replicates a range's value; later single designators override earlier range
   slots (PendingInit last-wins). gcc-verified. feature-c-compound-literals p3. */
static int hits[4];
static void s0(void){ hits[0]++; }
static void s1(void){ hits[1]++; }
static void s2(void){ hits[2]++; }
static void sni(void){ hits[3]++; }
typedef void (*fptr)(void);
const fptr table[3] = { [0 ... 2] = &sni, [0] = s0, [1] = s1, [2] = s2 };
int main(void) {
  int i;
  for (i = 0; i < 3; i++) table[i]();
  /* overrides win: s0,s1,s2 each once; sni never (all three slots overridden) */
  return (hits[0]==1 && hits[1]==1 && hits[2]==1 && hits[3]==0) ? 42 : 1;
}
