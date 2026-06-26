/* C `switch`: fallthrough, break (exits the switch), default, and a
   `continue` inside a switch that must target the ENCLOSING loop (break-only
   scope). Exit 3. */
int classify(int x) {
  int r = 0;
  switch (x) {
    case 1: r += 1;            /* fallthrough */
    case 2: r += 10; break;
    case 3: r += 100; break;
    default: r += 1000;
  }
  return r;
}
int sum_loop(void) {
  int s = 0, i;
  for (i = 0; i < 5; i++) {
    switch (i) {
      case 2: continue;        /* continue must target the for-loop */
      case 4: break;           /* break must exit the switch, not the loop */
      default: s += i;
    }
    s += 100;                  /* skipped when i==2 (continue), run otherwise */
  }
  return s;
}
int main(void) {
  /* classify: 1->11, 2->10, 3->100, 9->1000 */
  int a = classify(1) + classify(2) + classify(3) + classify(9);  /* 11+10+100+1000 = 1121 */
  int b = sum_loop();
  /* i=0:+0,+100; i=1:+1,+100; i=2:continue; i=3:+3,+100; i=4:+4,+100 => 0+1+3+4 + 4*100 = 408 */
  return (a == 1121) * 1 + (b == 404) * 2;   /* want 3 */
}
