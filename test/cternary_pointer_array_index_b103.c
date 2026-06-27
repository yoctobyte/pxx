/* A C ternary between two local arrays decays both arms to pointer values.
   Indexing the result must use the selected pointer value as the base address,
   not ask for the address of the ternary expression. sqlite uses this in
   balance_nonroot: (nNew>nOld ? apNew : apOld)[nOld-1]. Exit 42. */
struct Page {
  int id;
};

int pick(int use_new) {
  struct Page old0, old1, new0, new1;
  struct Page *apOld[2];
  struct Page *apNew[2];
  struct Page *p;

  old0.id = 10;
  old1.id = 17;
  new0.id = 30;
  new1.id = 42;
  apOld[0] = &old0;
  apOld[1] = &old1;
  apNew[0] = &new0;
  apNew[1] = &new1;

  p = (use_new ? apNew : apOld)[1];
  return p->id;
}

int main(void) {
  return pick(1);
}
