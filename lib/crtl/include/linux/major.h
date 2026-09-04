/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LINUX_MAJOR_H
#define PXX_CRTL_LINUX_MAJOR_H 1

/* <linux/major.h> -- the block and character device major numbers.

   Found attempting busybox on i386, where there is no host header to fall back
   on: miscutils/raidautorun.c includes it, and then includes
   <linux/raid/md_u.h>, whose RAID_AUTORUN is _IO(MD_MAJOR, 0x14). So the major
   number is not decoration here -- it is a FIELD OF AN IOCTL COMMAND, and
   getting it wrong issues a different ioctl on whatever device was opened
   rather than failing to compile.

   THE SECOND INCLUDE IS THE POINT OF THIS PARAGRAPH. The ticket that brought
   this file in listed exactly one header per translation unit, because it was
   built from FIRST refusals -- and a first-refusal list is a lower bound on
   every axis. raidautorun.c wants two, and the second was invisible until the
   first was supplied. Expect that of the others in that list too.

   These are Linux-ABI-wide: one table, no per-arch override, which is why
   there is no #if here. Generated from the kernel's own linux/major.h and
   diffed against it; the header is a numbering registry, so a stale entry is
   an absent NAME rather than a wrong value -- an absent one is still a compile
   error, which is the honest answer. */

#define UNNAMED_MAJOR                0
#define MEM_MAJOR                    1
#define RAMDISK_MAJOR                1
#define FLOPPY_MAJOR                 2
#define PTY_MASTER_MAJOR             2
#define IDE0_MAJOR                   3
#define PTY_SLAVE_MAJOR              3
#define TTY_MAJOR                    4
#define TTYAUX_MAJOR                 5
#define LP_MAJOR                     6
#define VCS_MAJOR                    7
#define LOOP_MAJOR                   7
#define SCSI_DISK0_MAJOR             8
#define SCSI_TAPE_MAJOR              9
#define MD_MAJOR                     9
#define MISC_MAJOR                   10
#define SCSI_CDROM_MAJOR             11
#define XT_DISK_MAJOR                13
#define INPUT_MAJOR                  13
#define SOUND_MAJOR                  14
#define CDU31A_CDROM_MAJOR           15
#define JOYSTICK_MAJOR               15
#define GOLDSTAR_CDROM_MAJOR         16
#define OPTICS_CDROM_MAJOR           17
#define SANYO_CDROM_MAJOR            18
#define MITSUMI_X_CDROM_MAJOR        20
#define SCSI_GENERIC_MAJOR           21
#define IDE1_MAJOR                   22
#define DIGICU_MAJOR                 22
#define DIGI_MAJOR                   23
#define MITSUMI_CDROM_MAJOR          23
#define CDU535_CDROM_MAJOR           24
#define MATSUSHITA_CDROM_MAJOR       25
#define MATSUSHITA_CDROM2_MAJOR      26
#define QIC117_TAPE_MAJOR            27
#define MATSUSHITA_CDROM3_MAJOR      27
#define MATSUSHITA_CDROM4_MAJOR      28
#define ACSI_MAJOR                   28
#define AZTECH_CDROM_MAJOR           29
#define MTD_BLOCK_MAJOR              31
#define CM206_CDROM_MAJOR            32
#define IDE2_MAJOR                   33
#define IDE3_MAJOR                   34
#define Z8530_MAJOR                  34
#define NETLINK_MAJOR                36
#define PS2ESDI_MAJOR                36
#define IDETAPE_MAJOR                37
#define Z2RAM_MAJOR                  37
#define RISCOM8_NORMAL_MAJOR         48
#define RISCOM8_CALLOUT_MAJOR        49
#define MKISS_MAJOR                  55
#define IDE4_MAJOR                   56
#define IDE5_MAJOR                   57
#define SCSI_DISK1_MAJOR             65
#define SCSI_DISK2_MAJOR             66
#define SCSI_DISK3_MAJOR             67
#define SCSI_DISK4_MAJOR             68
#define SCSI_DISK5_MAJOR             69
#define SCSI_DISK6_MAJOR             70
#define SCSI_DISK7_MAJOR             71
#define COMPAQ_SMART2_MAJOR          72
#define COMPAQ_SMART2_MAJOR1         73
#define COMPAQ_SMART2_MAJOR2         74
#define COMPAQ_SMART2_MAJOR3         75
#define COMPAQ_SMART2_MAJOR4         76
#define COMPAQ_SMART2_MAJOR5         77
#define COMPAQ_SMART2_MAJOR6         78
#define COMPAQ_SMART2_MAJOR7         79
#define SPECIALIX_NORMAL_MAJOR       75
#define SPECIALIX_CALLOUT_MAJOR      76
#define AURORA_MAJOR                 79
#define SCSI_CHANGER_MAJOR           86
#define IDE6_MAJOR                   88
#define IDE7_MAJOR                   89
#define IDE8_MAJOR                   90
#define MTD_CHAR_MAJOR               90
#define IDE9_MAJOR                   91
#define DASD_MAJOR                   94
#define MDISK_MAJOR                  95
#define UBD_MAJOR                    98
#define PP_MAJOR                     99
#define JSFD_MAJOR                   99
#define PHONE_MAJOR                  100
#define COMPAQ_CISS_MAJOR            104
#define COMPAQ_CISS_MAJOR1           105
#define COMPAQ_CISS_MAJOR2           106
#define COMPAQ_CISS_MAJOR3           107
#define COMPAQ_CISS_MAJOR4           108
#define COMPAQ_CISS_MAJOR5           109
#define COMPAQ_CISS_MAJOR6           110
#define COMPAQ_CISS_MAJOR7           111
#define VIODASD_MAJOR                112
#define VIOCD_MAJOR                  113
#define ATARAID_MAJOR                114
#define SCSI_DISK8_MAJOR             128
#define SCSI_DISK9_MAJOR             129
#define SCSI_DISK10_MAJOR            130
#define SCSI_DISK11_MAJOR            131
#define SCSI_DISK12_MAJOR            132
#define SCSI_DISK13_MAJOR            133
#define SCSI_DISK14_MAJOR            134
#define SCSI_DISK15_MAJOR            135
#define UNIX98_PTY_MASTER_MAJOR      128
#define UNIX98_PTY_MAJOR_COUNT       8
#define DRBD_MAJOR                   147
#define RTF_MAJOR                    150
#define RAW_MAJOR                    162
#define USB_ACM_MAJOR                166
#define USB_ACM_AUX_MAJOR            167
#define USB_CHAR_MAJOR               180
#define MMC_BLOCK_MAJOR              179
#define MSR_MAJOR                    202
#define CPUID_MAJOR                  203
#define IBM_TTY3270_MAJOR            227
#define IBM_FS3270_MAJOR             228
#define VIOTAPE_MAJOR                230
#define BLOCK_EXT_MAJOR              259

#endif /* PXX_CRTL_LINUX_MAJOR_H */
