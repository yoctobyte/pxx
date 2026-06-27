/* sqlite expands offsetof(Parse,sLastToken) inside an automatic array bound:
   char saveBuf[sizeof(Parse)-((size_t)&(((Parse *)0)->sLastToken))].
   The constant-expression folder must consume the field-address expression and
   return the field offset. Exit 42. */
typedef unsigned long size_t;
typedef struct Parse Parse;

struct Parse {
  int a;
  char b;
  long sLastToken;
};

int main(void) {
  char saveBuf[(sizeof(Parse)-((size_t)&(((Parse *)0)->sLastToken)))];
  saveBuf[0] = 1;
  return (int)sizeof(saveBuf) + 34;
}
