# cloud-images

Build recipes for cloud images that run on KVM/QEMU with cloud-init. Each recipe takes the vendor's official cloud image, verifies it, customises it offline and writes a compressed qcow2.

## What the build does

- Refuses to build when the OS is past end of life (checked against endoflife.date).
- Verifies the vendor checksum, and the vendor signature where one is published. Any mismatch stops the build.
- Installs and enables the QEMU guest agent, makes sure cloud-init is present.
- Enables root login over SSH with a password, and keeps SSH host keys across cloud-init instance changes (`ssh_deletekeys: false`).
- Installs a one-time first-boot update. `security` applies security updates only, `full` upgrades everything.
- Installs curl, wget, nano, vim, htop, ca-certificates, unzip and bash-completion (htop is skipped on AlmaLinux, Rocky Linux and CentOS Stream, where it needs EPEL), sets UTC and `en_US.UTF-8`, and makes sure firewalld and ufw are not enabled.
- Creates a swap file on first boot unless the image already has swap: 1 GiB when RAM is 2 GiB or less, 2 GiB up to 8 GiB, none above.
- On SELinux distributions the labels are rewritten at the end of the build and SELinux stays enforcing; guest agent commands (exec, file access) are not blocked.
- Removes machine id, SSH host keys, logs, package caches and cloud-init state, then trims and compresses.
- Writes `output/<name>-<version>-<YYYYMMDD>.qcow2`, a `.sha256` file and a `.json` manifest with source, checksums and the installed package list.

## Recipes

`os/<distro>/<version>.yaml`. Fields: `name`, `version`, `arch`, `package_manager` (`apt`, `dnf`, `zypper`, `pacman`, `pkg`), `first_boot_update`, `source.url`, `checksum` (`url`, `algo`), optional `signature`, optional `eol` (`product`, `cycle`; omitted for rolling releases), optional `selinux_relabel`, `disable_kdump` (turn off kdump and drop the `crashkernel` memory reservation), `grow` (`partition`, `size`: enlarge a too-small vendor image before customising), `kernel_args`.

`signature` is either `keyring` (a system keyring file) or `key` (an armored key in `keys/`) plus `fingerprint` (checked against the key file). `kind` is `detached` (default) or `clearsign` (the checksum file itself), and `target: image` verifies the signature over the image instead of the checksum file.

Available: Ubuntu 22.04, 24.04, 26.04; Debian 12, 13; AlmaLinux 8, 9, 10; Rocky Linux 8, 9, 10; CentOS Stream 9, 10; Fedora 43, 44; openSUSE Leap 16.0; Arch Linux; FreeBSD 14.5, 15.1.

## Usage

```
./build os/debian/13.yaml
./test output/debian-13-<date>.qcow2
```

Builds and tests run on Linux with KVM. Required: qemu-system-x86, qemu-utils, libguestfs-tools, cloud-image-utils, genisoimage, openssh-client, sshpass, gnupg, python3 with PyYAML, and the keyring named in a recipe's `signature.keyring` (for Ubuntu, `ubuntu-keyring`).

For SELinux guests the libguestfs appliance needs `setfiles`: install `policycoreutils` on the builder and add it to the appliance package list (`/usr/lib/x86_64-linux-gnu/guestfs/supermin.d/packages` on Debian and Ubuntu), then delete the cached appliance in `/var/tmp/.guestfs-*`. Without it libguestfs only marks the image for relabelling at first boot, and the relabel never gets to run.

The libguestfs appliance forwards DNS to the host's `/etc/resolv.conf`. If that points at a local stub resolver such as 127.0.0.53, point it at a real upstream resolver first, or package installs inside the image fail.

See [TESTING.md](TESTING.md) for what the tests check.

## Notes

- FreeBSD (`package_manager: pkg`) is built by `build-bsd`: the official BASIC-CLOUDINIT image is booted once with a build seed, customised over SSH (cloud-init and qemu-guest-agent from pkg, sshd root and password login, UTC), then cleaned and shut down. It runs cloud-init in place of nuageinit so `password`, `chpasswd` and network-config v1 apply. cloud-init renames the matched NIC to `eth0`, as on Linux. The first-boot update runs `freebsd-update fetch install` and `pkg upgrade`.

- Debian, CentOS Stream and Rocky Linux 8 publish no signature that the recipes can use, so those recipes rely on the checksum fetched over HTTPS. The keys in `keys/` were fetched from the vendors' own sites (Arch from a keyserver); their fingerprints are pinned in the recipes.
- Fedora recipes name a specific build (for example `Fedora-Cloud-Base-Generic-44-1.7`), because Fedora publishes no `latest` file; bump them when a new build ships.
- Arch Linux is built from the arch-boxes cloudimg; the build runs a full `pacman -Syu` (the kernel hook needs `/dev/stdin`, which the build creates). Ubuntu 26.04 gets `net.ifnames=0` on the kernel command line: its initramfs brings the NIC up before cloud-init runs, so cloud-init cannot rename it to `eth0`.
- Downloads are cached in `cache/`. Outputs go to `output/`.

## Licence

MIT. Distro images keep their own licences and trademarks.
