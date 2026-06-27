typedef unsigned char lu_byte;

#define CommonHeader struct GCObject *next; lu_byte tt; lu_byte marked

typedef struct GCObject {
  CommonHeader;
} GCObject;

static GCObject **getslot(GCObject **p) {
  return p;
}

int main(void) {
  GCObject a;
  GCObject b;
  GCObject *head;
  GCObject *got;
  a.next = &b;
  head = &a;
  got = *getslot(&head);
  if (got != &a) return 1;
  return got->next == &b ? 42 : 2;
}
