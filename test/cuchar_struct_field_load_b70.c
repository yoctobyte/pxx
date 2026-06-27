typedef unsigned char lu_byte;

typedef struct FuncState {
  int firstlabel;
  short ndebugvars;
  lu_byte nactvar;
  lu_byte nups;
  lu_byte freereg;
} FuncState;

int main(void) {
  FuncState fs;
  fs.firstlabel = 0x010000ff;
  fs.ndebugvars = 0x7f7f;
  fs.nactvar = 3;
  fs.nups = 1;
  fs.freereg = 2;

  if (fs.nactvar != 3) return 1;
  if ((int)fs.nactvar != 3) return 3;
  if (fs.nups != 1) return 2;
  return (int)fs.nactvar + fs.nups + fs.freereg + 36;
}
