#!/usr/bin/env python3
"""One-time: log in on the serial console as root and install the ssh key."""
import os, sys, pexpect
os.chdir(sys.argv[1])
key = open("id_vm.pub").read().strip()
# $QEMU is freebsd.sh's machine (amd64 under KVM, or arm64 under TCG, whose
# first boot also applies base-system updates and takes many minutes).
p = pexpect.spawn(" ".join(os.environ["QEMU"].split()) + " -nographic "
                  "-drive file=fbsd.qcow2,if=virtio,format=qcow2 "
                  "-netdev user,id=n0 -device virtio-net-pci,netdev=n0",
                  encoding="utf-8", timeout=1800, logfile=open("setup.log", "w"))
p.expect("login: ")
p.sendline("root")
i = p.expect([r"Password:", r"root@.*[#$] ", r"# "])
if i == 0:
    raise SystemExit("root has a password on the console")
for cmd in ["mkdir -p /root/.ssh && chmod 700 /root/.ssh",
            "echo '%s' > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys" % key,
            "sysrc sshd_enable=YES",
            "grep -q '^PermitRootLogin' /etc/ssh/sshd_config || echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config",
            "echo SETUP-DONE"]:
    p.sendline(cmd)
p.expect("\nSETUP-DONE")
p.sendline("shutdown -p now")
p.expect(pexpect.EOF, timeout=600)
print("OK")
