/* sizeof on a VLA is a runtime value, so it cannot size another array's
   fixed bound. The refusal must be LOUD: the companion symbol that carries
   the runtime size is an identifier, and its ASTIVal is a symbol INDEX --
   accepting it here would silently size the array with a symbol number.
   feature-c-vla-via-alloca */
int main(void)
{
  int n = 5;
  int vla[n];
  int fixed[sizeof(vla)];
  fixed[0] = 0;
  return fixed[0];
}
