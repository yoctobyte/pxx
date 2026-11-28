/* SPDX-License-Identifier: Zlib */
/* scandir with versionsort: digit runs sort as numbers (event9 < event10),
   as libinput lists its devices. Row c_vsort26 runs it on a directory of
   empty files, against gcc. feature-crtl-versionsort */
#define _GNU_SOURCE
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
static int nodots(const struct dirent *d){ return d->d_name[0] != '.'; }
int main(int c, char **v){ struct dirent **l; int n = scandir(v[1], &l, nodots, versionsort), i; for (i = 0; i < n; i++) { printf("%s\n", l[i]->d_name); free(l[i]); } free(l); return n < 0; }
