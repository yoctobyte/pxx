/* A struct containing a bit-field (directly or via a nested bit-field struct,
   as in sqlite3's `struct sqlite3InitInfo { ... :1; } init;`) must still be laid
   out as a record — the old code fell back to an opaque pointer on ANY bit-field,
   which dropped every field including sibling function-pointer members, so a
   later `db->xProgress(...)` call could not resolve. Bit-fields are laid out as a
   full storage unit (no bit-packing); access is by name. Exit 42. */
struct DB {
  int a;
  struct Init {
    unsigned newTnum;
    unsigned char iDb;
    unsigned orphanTrigger : 1;
    unsigned imposterTable : 1;
    const char **azInit;
  } init;
  void *pArg;
  int (*xProgress)(void *);
};
int cb(void *p){ return 42; }
static int step(struct DB *db){
  if( db->xProgress ){ if( db->xProgress(db->pArg) ){ return db->init.iDb; } }
  return 0;
}
int main(void){
  struct DB d; d.xProgress = cb; d.pArg = 0; d.init.iDb = 42;
  d.init.orphanTrigger = 1;
  return step(&d);
}
