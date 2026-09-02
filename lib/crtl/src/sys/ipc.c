/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: ftok(3).
 *
 * ftok IS NOT A HASH. POSIX and every Unix implement it as three fields packed
 * into 32 bits: the low 8 bits of proj_id, the low 8 bits of the device MINOR
 * number, and the low 16 bits of the inode. So its collisions are structural,
 * not statistical -- two files on one filesystem whose inodes differ only
 * above bit 16 produce the same key, and the caller then attaches to somebody
 * else's segment. Anything cleverer here would be WRONG rather than better:
 * two programs that agree on a path must agree on the key, and they only do
 * that if every implementation computes the same three fields.
 *
 * The minor number is taken through <sys/sysmacros.h> rather than by masking
 * st_dev directly, because the userspace dev_t encoding is not contiguous --
 * minor bits live at 0..7 and 12..31.
 */
#include <sys/ipc.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>

key_t ftok(const char *pathname, int proj_id)
{
  struct stat st;

  if (stat(pathname, &st) < 0)
    return (key_t) -1;

  return (key_t)((st.st_ino & 0xffff)
                 | ((minor(st.st_dev) & 0xff) << 16)
                 | ((proj_id & 0xff) << 24));
}
