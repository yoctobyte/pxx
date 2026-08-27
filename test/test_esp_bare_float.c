/* The C-frontend half of bug-a-esp32c3-bare-profile-cannot-find-the-softfloat-
   repack-helper: a bare ESP translation unit with a float in it.

   Build-only, deliberately. The Pascal companion (test_esp_bare_float.pas)
   carries the value oracle; this file exists because the C driver had its OWN
   copy of the "may I pull an RTL unit" guard and its own blind spot, and a fix
   applied to one frontend and not the other is exactly the double-case
   devdocs/dev/normalise-dont-special-case.md warns about. C on xtensa stops
   earlier still ("C program entry stub not implemented for this target yet"),
   which is a separate gap, so the riscv32 spellings are what this row covers. */
float g[4];

int main(void)
{
  int    x = 3;
  double d;
  g[0] = x;            /* __pxx_i2s  */
  g[1] = g[0] * 2.5f;  /* single mul */
  d    = g[1];         /* __pxx_s2d  */
  g[2] = d + 0.5;      /* double add, then __pxx_d2s */
  return (int)g[2];
}
