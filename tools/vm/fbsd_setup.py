#!/usr/bin/env python3
"""One-time: log in on the serial console as root and install the ssh key."""
import os, sys, pexpect
os.chdir(sys.argv[1])
key = open("id_vm.pub").read().strip()
p = pexpect.spawn("qemu-system-x86_64 -enable-kvm -m 2048 -smp 2 -nographic "
                  "-drive file=fbsd.qcow2,if=virtio,format=qcow2 "
                  "-netdev user,id=n0 -device virtio-net-pci,netdev=n0",
                  encoding="utf-8", timeout=300, logfile=open("setup.log", "w"))
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
p.expect(pexpect.EOF, timeout=180)
print("OK")
