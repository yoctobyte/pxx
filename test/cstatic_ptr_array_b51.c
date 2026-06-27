/* Static/local char-pointer array initializer must retain full 64-bit string
   addresses. Lua's luaT_eventname[] is this shape. Exit 42. */
static const char *const global_names[] = {"ab", "cd"};

int main(void) {
  static const char *const local_names[] = {"xy", "zt"};
  return global_names[0][0] + global_names[1][1] +
         local_names[0][0] + local_names[1][1] - 391;
}
