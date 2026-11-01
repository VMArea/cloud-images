# cloud-images

Build recipes for cloud images that run on KVM/QEMU with cloud-init. Each recipe takes the vendor's official cloud image, verifies it, customises it offline and writes a compressed qcow2.

## What the build does

- Refuses to build when the OS is past end of life (checked against endoflife.date).
- Verifies the vendor checksum, and the vendor signature where one is published. Any mismatch stops the build.
- Installs and enables the QEMU guest agent, makes sure cloud-init is present.
- Enables root login over SSH with a password, and keeps SSH host keys across cloud-init instance changes (`ssh_deletekeys: false`).
- Installs a one-time first-boot update. `security` applies security updates only, `full` upgrades everything.
- Removes machine id, SSH host keys, logs, package caches and cloud-init state, then trims and compresses.
- Writes `output/<name>-<version>-<YYYYMMDD>.qcow2`, a `.sha256` file and a `.json` manifest with source, checksums and the installed package list.

## Recipes

`os/<distro>/<version>.yaml`. Fields: `name`, `version`, `arch`, `package_manager`, `first_boot_update`, `source.url`, `checksum` (`url`, `algo`, `format`), optional `signature` (`url`, `keyring`), `eol` (`product`, `cycle`).

Available: `os/debian/13.yaml`, `os/ubuntu/24.04.yaml`.

## Usage

```
./build os/debian/13.yaml
./test output/debian-13-<date>.qcow2
```

Builds and tests run on Linux with KVM. Required: qemu-system-x86, qemu-utils, libguestfs-tools, cloud-image-utils, genisoimage, openssh-client, sshpass, gnupg, python3 with PyYAML, and the keyring named in a recipe's `signature.keyring` (for Ubuntu, `ubuntu-keyring`).

The libguestfs appliance forwards DNS to the host's `/etc/resolv.conf`. If that points at a local stub resolver such as 127.0.0.53, point it at a real upstream resolver first, or package installs inside the image fail.

See [TESTING.md](TESTING.md) for what the tests check.

## Notes

- Debian publishes no signature for its cloud image checksum file, so the Debian recipe relies on the checksum fetched over HTTPS.
- Downloads are cached in `cache/`. Outputs go to `output/`.

## Licence

MIT. Distro images keep their own licences and trademarks.
