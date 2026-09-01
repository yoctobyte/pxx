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
   passes while 0F BE/0F BF are wrong. */

long long      g_ll   = 0x1122334455667788LL;
int            g_i    = -70000;
unsigned char  g_u8   = 200;
signed char    g_s8   = -100;
unsigned short g_u16  = 60000;
short          g_s16  = -30000;
int            g_arr[4] = {11, 22, 33, 44};

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
  return k + (int)(ll >> 32) + g_i + g_u8 + g_s8 + g_u16 + g_s16 + acc;
}
