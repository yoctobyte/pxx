/* A struct/union containing a double returned by value: needs ProcRetRecId +
   the hidden aggregate-dest convention on the C callee/caller. Segfaulted before. */
typedef union U { double n; long i; } U;
static U mk(double x) { U u; u.n = x; return u; }
int main(void) {
  U u = mk(2.5);
  return (u.n == 2.5 && (u.i >> 32) != 0) ? 42 : 1;
}
