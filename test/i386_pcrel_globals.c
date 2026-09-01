/* SUBJECT for the i386 PC-relative data reference (TryI386PcRelLoad, emit.inc).
   Compiled by pxx with --target=i386 --emit-obj; the main is
   test/i386_pcrel_globals_host.c, built by gcc -m32.

   WHY THIS FILE EXISTS AT ALL. test-emit-obj's i386 rows and
   test-c-abi-mixed-link both PASS against a compiler whose PC-relative addend
   is deliberately wrong by 0x30000000 -- MEASURED, not argued. They convert
   sites and never execute one, so they are blind to every defect in this
   conversion while looking like coverage of it. Against the same corrupted
   compiler this file segfaults, which is the property that makes it a guard.

   So: EVERY GLOBAL BELOW IS READ, and its value asserted. A row that only
   compiles proves nothing here. The shapes are chosen to cover the whole
   converted opcode set -- 8B (dword/the halves of a long long), 8A/0F B6
   (unsigned char), 0F BE (signed char), 0F B7 (unsigned short), 0F BF (short)
   -- because the conversion rewrites ModRM identically for all of them and a
   sibling opcode left out of the subject is the one that stays broken.

   The signed rows are not decoration: sign-extension and zero-extension use
   different opcodes with the same ModRM, and a subject with only unsigned rows
   passes while 0F BE/0F BF are wrong.

   Three FAMILIES are covered, not one, because they convert through different
   code and a subject that exercises only the first is a guard for only the
   first:
     - ModRM loads              -- the plain reads of g_i, g_u8, g_arr[k] below
     - moffs loads (A0/A1)      -- same reads, when the emitter picks the eax form
     - address-as-immediate     -- `&g_i` and the string literal, which become
       (B8+r, rewritten to lea)    `lea reg,[reg+disp32]` off the anchor rather
                                   than a load, and which nothing in the value
                                   rows above would touch. */

long long      g_ll   = 0x1122334455667788LL;
int            g_i    = -70000;
unsigned char  g_u8   = 200;
signed char    g_s8   = -100;
unsigned short g_u16  = 60000;
short          g_s16  = -30000;
int            g_arr[4] = {11, 22, 33, 44};
const char     g_msg[] = "pcrel";
int           *g_pi = &g_i;      /* address-of at file scope: a .data relocation */

int pic_probe(int k)
{
  long long ll = g_ll;
  int acc;
  if (ll != 0x1122334455667788LL) return 101;
  if (g_i != -70000)              return 102;
  if (g_u8 != 200)                return 103;
  if (g_s8 != -100)               return 104;
  if (g_u16 != 60000)             return 105;
  if (g_s16 != -30000)            return 106;
  acc = g_arr[0] + g_arr[1] + g_arr[2] + g_arr[3];
  if (acc != 110)                 return 107;

  /* ADDRESS-OF, the family that becomes `lea` rather than a load. Taken AND
     dereferenced -- a pointer that is merely non-null proves nothing here, the
     same way `@external <> nil` did not in test_external_proc_addr_callable. */
  {
    int *p = &g_i;
    const char *m = g_msg;
    if (p != g_pi)                return 108;
    if (*p != -70000)             return 109;
    if (m[0] != 'p' || m[1] != 'c' || m[2] != 'r' ||
        m[3] != 'e' || m[4] != 'l' || m[5] != 0) return 110;
    if (&g_arr[2] - &g_arr[0] != 2) return 111;
    if (*(&g_arr[3]) != 44)       return 112;
  }
  return k + (int)(ll >> 32) + g_i + g_u8 + g_s8 + g_u16 + g_s16 + acc;
}
