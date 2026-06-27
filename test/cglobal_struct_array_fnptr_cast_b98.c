/* File-scope struct-array initializer with a function-pointer cast field.
   sqlite's aSyscall table uses this shape: the field must receive the function
   body address during PendingInit materialization, not zero/garbage. Exit 42. */
typedef int (*syscall_ptr)(const char *, int, int);

static int posixOpen(const char *z, int f, int m) {
  return 42;
}

static struct unix_syscall {
  const char *zName;
  syscall_ptr pCurrent;
  int flags;
} aSyscall[] = {
  { "open", (syscall_ptr)posixOpen, 7 },
};

#define osOpen ((int(*)(const char*,int,int))aSyscall[0].pCurrent)

int main(void) {
  return osOpen("*", 0, 0);
}
