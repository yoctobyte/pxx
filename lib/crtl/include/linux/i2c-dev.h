/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/i2c-dev.h> -- the /dev/i2c-N ioctl numbers.
 *
 * I2C_SLAVE AND I2C_SLAVE_FORCE DIFFER ONLY IN WHETHER THE KERNEL CHECKS. The
 * forcing one binds an address a driver already claims, which is exactly what
 * `i2cget -f' is for and exactly what corrupts a running device when it is
 * reached by accident. Two adjacent numbers, one of them a loaded gun.
 *
 * The structs these requests carry are in <linux/i2c.h>; the kernel splits
 * them the same way, and this file is only numbers.
 *
 * Found attempting busybox on i386: miscutils/i2c_tools.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_LINUX_I2C_DEV_H
#define _CRTL_LINUX_I2C_DEV_H

#include <linux/types.h>
#include <linux/i2c.h>   /* struct i2c_msg, union i2c_smbus_data */

/* /dev/i2c-X ioctl commands.  The ioctl's parameter is always an
 * unsigned long, except for:
 *	- I2C_FUNCS, takes pointer to an unsigned long
 *	- I2C_RDWR, takes pointer to struct i2c_rdwr_ioctl_data
 *	- I2C_SMBUS, takes pointer to struct i2c_smbus_ioctl_data
 */
#define I2C_RETRIES	0x0701	/* number of times a device address should
				   be polled when not acknowledging */
#define I2C_TIMEOUT	0x0702	/* set timeout in units of 10 ms */

/* NOTE: Slave address is 7 or 10 bits, but 10-bit addresses
 * are NOT supported! (due to code brokenness)
 */
#define I2C_SLAVE	0x0703	/* Use this slave address */
#define I2C_SLAVE_FORCE	0x0706	/* Use this slave address, even if it
				   is already in use by a driver! */
#define I2C_TENBIT	0x0704	/* 0 for 7 bit addrs, != 0 for 10 bit */

#define I2C_FUNCS	0x0705	/* Get the adapter functionality mask */

#define I2C_RDWR	0x0707	/* Combined R/W transfer (one STOP only) */

#define I2C_PEC		0x0708	/* != 0 to use PEC with SMBus */
#define I2C_SMBUS	0x0720	/* SMBus transfer */

/* This is the structure as used in the I2C_SMBUS ioctl call */
struct i2c_smbus_ioctl_data {
	__u8 read_write;
	__u8 command;
	__u32 size;
	union i2c_smbus_data *data;
};

/* This is the structure as used in the I2C_RDWR ioctl call */
struct i2c_rdwr_ioctl_data {
	struct i2c_msg *msgs;	/* pointers to i2c_msgs */
	__u32 nmsgs;			/* number of i2c_msgs */
};

#define  I2C_RDWR_IOCTL_MAX_MSGS	42
/* Originally defined with a typo, keep it for compatibility */
#define  I2C_RDRW_IOCTL_MAX_MSGS	I2C_RDWR_IOCTL_MAX_MSGS

#endif
