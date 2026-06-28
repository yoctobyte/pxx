struct Holder {
  int tag;
  struct Item {
    int value;
  } *items;
  int count;
};

int main(void) {
  struct Item rows[2];
  struct Holder h;
  rows[0].value = 11;
  rows[1].value = 31;
  h.tag = 7;
  h.items = rows;
  h.count = 2;
  return h.tag + h.items[0].value + h.items[1].value - h.count - 5;
}
