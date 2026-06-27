typedef int (*Fn)(void);

typedef struct Reg {
  const char *name;
  Fn func;
} Reg;

int f(void) { return 30; }
int g(void) { return 12; }

static const Reg regs[] = {
  {"f", f},
  {"g", g},
  {0, 0}
};

int main(void) {
  if (regs[0].name[0] != 'f') return 1;
  if (regs[1].name[0] != 'g') return 2;
  if (regs[2].name != 0) return 3;
  if (regs[2].func != 0) return 4;
  return regs[0].func() + regs[1].func();
}
