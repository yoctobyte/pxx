static int run(int op, int cur) {
  int v = 0;
  switch (op) {
    case 111: {
      int local = 3;
      if (cur == 1) {
        v = 10 + local;
        goto done;
      }
      /* fall through while still inside the compound block */
    case 112:
    case 113:
      v = 40;
      break;
    }
    case 36:
      v = 1;
      break;
    default:
      v = 5;
      break;
  }
done:
  return v + op - 111;
}

int main(void) {
  if (run(111, 1) != 13) return 1;
  if (run(111, 0) != 40) return 2;
  if (run(112, 0) != 41) return 3;
  if (run(113, 0) != 42) return 4;
  if (run(36, 0) != -74) return 5;
  if (run(250, 0) != 144) return 6;
  return 42;
}
