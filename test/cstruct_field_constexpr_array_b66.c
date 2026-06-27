#define BUFSZ (16 + 3 + 5)

typedef struct Buff {
  void *L;
  int pushed;
  int blen;
  char space[BUFSZ];
} Buff;

int main(void) {
  Buff b;
  long guard = 0x1122334455667788L;

  b.L = 0;
  b.pushed = 1;
  b.blen = 2;
  b.space[23] = 39;

  if (sizeof(Buff) != 40) return 1;
  if (guard != 0x1122334455667788L) return 2;
  return b.space[23] + 3;
}
