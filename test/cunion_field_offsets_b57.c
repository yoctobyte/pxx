/* Adjacent union fields in a struct must keep distinct aligned offsets.
   Lua's lua_State has top/stack_last/stack/tbclist StkIdRel unions. Exit 42. */
typedef union { void *p; long offset; } Rel;

struct Thread {
  void *next;
  unsigned char tt;
  unsigned char marked;
  unsigned char status;
  unsigned char allowhook;
  unsigned short nci;
  Rel top;
  void *g;
  void *ci;
  Rel stack_last;
  Rel stack;
  void *openupval;
  Rel tbclist;
};

int main(void) {
  struct Thread L;
  char *base = (char *)&L;
  int off_top = (int)((char *)&L.top - base);
  int off_stack_last = (int)((char *)&L.stack_last - base);
  int off_stack = (int)((char *)&L.stack - base);
  int off_tbclist = (int)((char *)&L.tbclist - base);

  L.top.offset = 1;
  L.stack_last.offset = 2;
  L.stack.p = (void *)0x1234567887654321UL;
  L.tbclist.offset = 3;

  if (off_top != 16 || off_stack_last != 40 || off_stack != 48 || off_tbclist != 64)
    return 100;
  if (L.stack.p != (void *)0x1234567887654321UL)
    return 101;
  return 42;
}
