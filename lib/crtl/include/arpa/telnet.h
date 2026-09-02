/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <arpa/telnet.h> -- the TELNET protocol constants (RFC 854 and
 * the option registry).
 *
 * PURE PROTOCOL NUMBERS, frozen by the RFCs and by IANA rather than by any
 * libc, which is why this file can exist at all without becoming a fork of
 * someone else's header: there is nothing here a future version could change.
 *
 * The command byte values (SE..IAC) run DOWNWARD from 255, so `IAC' is 255 and
 * `SE' is 240; getting one wrong does not fail to compile, it puts a different
 * command on the wire, and the two ends then disagree about where the
 * subnegotiation ended. Every value is diffed against the host's own copy by
 * test/c_crtl_telnet_and_prctl.c.
 *
 * Found attempting busybox on i386: networking/telnet.c and telnetd.c, which
 * between them use IAC, WILL/WONT/DO/DONT, SB/SE, NOP, AYT, GA and the
 * TELOPT_ECHO/SGA/TTYPE/NAWS/LFLOW options.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_ARPA_TELNET_H
#define _CRTL_ARPA_TELNET_H

/* Commands. IAC introduces every one of them. */
#define xEOF  236   /* the name EOF is taken by <stdio.h>, as in glibc */
#define SUSP  237
#define ABORT 238
#define EOR   239
#define SE    240   /* end of subnegotiation */
#define NOP   241
#define DM    242   /* data mark */
#define BREAK 243
#define IP    244   /* interrupt process */
#define AO    245   /* abort output */
#define AYT   246   /* are you there */
#define EC    247   /* erase character */
#define EL    248   /* erase line */
#define GA    249   /* go ahead */
#define SB    250   /* begin subnegotiation */
#define WILL  251
#define WONT  252
#define DO    253
#define DONT  254
#define IAC   255   /* interpret as command */

/* Options, from IANA's registry. */
#define TELOPT_BINARY         0
#define TELOPT_ECHO           1
#define TELOPT_RCP            2
#define TELOPT_SGA            3   /* suppress go ahead */
#define TELOPT_NAMS           4
#define TELOPT_STATUS         5
#define TELOPT_TM             6   /* timing mark */
#define TELOPT_RCTE           7
#define TELOPT_NAOL           8
#define TELOPT_NAOP           9
#define TELOPT_NAOCRD        10
#define TELOPT_NAOHTS        11
#define TELOPT_NAOHTD        12
#define TELOPT_NAOFFD        13
#define TELOPT_NAOVTS        14
#define TELOPT_NAOVTD        15
#define TELOPT_NAOLFD        16
#define TELOPT_XASCII        17
#define TELOPT_LOGOUT        18
#define TELOPT_BM            19
#define TELOPT_DET           20
#define TELOPT_SUPDUP        21
#define TELOPT_SUPDUPOUTPUT  22
#define TELOPT_SNDLOC        23
#define TELOPT_TTYPE         24   /* terminal type */
#define TELOPT_EOR           25
#define TELOPT_TUID          26
#define TELOPT_OUTMRK        27
#define TELOPT_TTYLOC        28
#define TELOPT_3270REGIME    29
#define TELOPT_X3PAD         30
#define TELOPT_NAWS          31   /* window size */
#define TELOPT_TSPEED        32   /* terminal speed -- the one this file was
                                     first written WITHOUT, which shifted LFLOW,
                                     LINEMODE and XDISPLOC each down by one and
                                     compiled perfectly. The oracle row caught
                                     it; nothing else could have. */
#define TELOPT_LFLOW         33   /* remote flow control */
#define TELOPT_LINEMODE      34
#define TELOPT_XDISPLOC      35
#define TELOPT_OLD_ENVIRON   36
#define TELOPT_AUTHENTICATION 37
#define TELOPT_ENCRYPT       38
#define TELOPT_NEW_ENVIRON   39
#define TELOPT_EXOPL        255

/* Subnegotiation qualifiers, shared by TTYPE, XDISPLOC and the ENVIRONs. */
#define TELQUAL_IS    0
#define TELQUAL_SEND  1
#define TELQUAL_INFO  2

#endif
