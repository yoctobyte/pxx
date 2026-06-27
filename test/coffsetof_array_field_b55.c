/* offsetof-style address-of an array field after a union must keep the field
   offset. Lua's sizelstring uses offsetof(TString, contents). Exit 42. */
struct T {
  void *next;
  unsigned char tt;
  unsigned char marked;
  unsigned char extra;
  unsigned char shrlen;
  unsigned int hash;
  union { unsigned long len; struct T *hnext; } u;
  char contents[1];
};

int main(void) {
  int off = (int)(long)&(((struct T *)0)->contents);
  int sz = (int)sizeof(struct T);
  return off + sz - 14;   /* 24 + 32 - 14 = 42 */
}
