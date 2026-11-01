# Testing

`./test <image.qcow2>` boots two instances of the image under QEMU with KVM and checks them. It prints one PASS or FAIL line per check, a summary, and exits non-zero if anything failed. QEMU processes and the work directory are always cleaned up.

## Setup mirrored from production

- Disk on a virtio-scsi controller, grown to 20G through a qcow2 overlay. Cloud-init seed as a CD-ROM (NoCloud, label `cidata`). VGA std. Virtio NIC with a fixed MAC, user networking with an SSH port forward. Guest agent on a virtio-serial port.
- user-data: `hostname`, `manage_etc_hosts`, `fqdn`, `user: root`, `disable_root: False`, `password`, `chpasswd.expire: False`, `package_upgrade: true`, `ssh_authorized_keys`. There is no `ssh_pwauth` line, so the image has to enable password SSH itself. `--no-package-upgrade` drops the `package_upgrade` line.
- network-config v1: physical `eth0` matched by MAC, DHCP, nameserver 1.1.1.1.
- Hostname is `vmarea-test-hostname-0123`.

## Checks

Before booting, the image itself is inspected read-only: `/etc/vmarea/README.txt` is present and unchanged; every file the build adds carries the header `# Managed by VMArea. See /etc/vmarea/README.txt`; `/root` holds only distro default dotfiles and no `*_history` file; `/home`, `/tmp` and `/var/tmp` are empty; machine id is empty and there are no SSH host keys; no journal, no non-empty logs (other than lastlog, wtmp, btmp, faillog), no cloud-init state, no package caches or package lists, no build files in `/`. The manifest must record no pending package updates (the build fails if `apt-get -s dist-upgrade`, `dnf check-update`, `zypper lu` or `pacman -Qu` still list anything after the full upgrade).

Then the image boots and is checked: cloud-init finished with no errors; SSH with key; SSH with root password; hostname and fqdn; root filesystem grown (over 17 GiB of the 20G disk; Ubuntu keeps a separate 1G boot partition, so 19G is not reachable there); NIC named eth0 with a default route; DNS resolves; first-boot update marker with exit status 0; guest agent `guest-ping`, `guest-get-osinfo`, `guest-exec` plus `guest-exec-status`, `guest-network-get-interfaces`, `guest-fsfreeze-status`, and file open/write/close; SSH host keys and machine id differ between two instances of the same image; getty on tty1 is active and root has a usable password; swap file of 1 GiB (RAM up to 2 GiB) or 2 GiB (up to 8 GiB), mode 600, in fstab and active, unless the image shipped its own swap (Arch, Fedora zram); curl, wget, nano, vi, unzip, htop (not on AlmaLinux, Rocky Linux and CentOS Stream), bash-completion and the CA bundle present; firewalld and ufw neither enabled nor active; time zone UTC and `en_US.UTF-8` generated and configured.

A password reset is then simulated on the first instance: new instance-id and new password, same disk. The new password must work, the old one must be rejected, SSH host keys and hostname must not change.

Differences in what the checks accept: RHEL-family `passwd -S` prints `PS` for a set password; Ubuntu 26.04 needs `net.ifnames=0` on the kernel command line (see README); the test VM gets a fixed SMBIOS UUID per instance so that FreeBSD derives a distinct host id.

## Negative case

`./test-negative <unmodified upstream image>` runs the same harness against the vendor image and passes only if `test` fails.

Result on the unmodified Debian 13 genericcloud image (2026-11-01): 12 passed, 10 failed. Failed: root password SSH login, first-boot update, all seven guest agent checks, new password after reset, host keys unchanged after reset (the upstream image regenerates host keys on a new instance). `test-negative` exited 0.

## Results for the customised images (2026-11-01)

| Image | Seed | Result |
|---|---|---|
| debian-13 | with `package_upgrade` | 22 passed, 0 failed |
| debian-13 | `--no-package-upgrade` | 22 passed, 0 failed |
| ubuntu-24.04 | with `package_upgrade` | 22 passed, 0 failed |
