#!/bin/sh
set -e
export ASSUME_ALWAYS_YES=yes
pkg update -f
pkg install -y py312-cloud-init qemu-guest-agent curl nano htop ca_root_nss bash
sysrc -x nuageinit_enable || true
sysrc -x firstboot_freebsd_update_enable || true
sysrc cloudinit_enable=YES
sysrc qemu_guest_agent_enable=YES
sed -i '' '/^PermitRootLogin prohibit-password$/d' /etc/ssh/sshd_config
printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' | cat - /etc/ssh/sshd_config > /etc/ssh/sshd_config.new
mv /etc/ssh/sshd_config.new /etc/ssh/sshd_config
cp /usr/share/zoneinfo/UTC /etc/localtime
rm -f /etc/rc.conf.d/hostname
sysrc hostname=freebsd
cfg=/usr/local/etc/cloud/cloud.cfg
sed -i '' -e '/^    doas:$/d' -e '/permit nopass freebsd/d' -e '/^    sudo:/d' $cfg
printf 'resize_rootfs: false\ngrowpart:\n  mode: "off"\n' >> /usr/local/etc/cloud/cloud.cfg.d/90-vmarea.cfg
echo "FIRST_BOOT_UPDATE=${FIRST_BOOT_UPDATE}" > /etc/vmarea/image.conf
mkdir -p /var/lib/cloud/scripts/per-once
cp /tmp/per-once-wrapper /var/lib/cloud/scripts/per-once/10-vmarea-first-boot-update
chmod 755 /var/lib/cloud/scripts/per-once/10-vmarea-first-boot-update
pw userdel freebsd -r || true
pkg query '%n %v' > /var/vmarea-pkglist
echo "freebsd-base $(freebsd-version -u)" >> /var/vmarea-pkglist
pkg clean -ay
rm -f /var/db/pkg/repo-*.sqlite
HDR='# Managed by VMArea. See /etc/vmarea/README.txt'
for f in /usr/local/etc/cloud/cloud.cfg.d/90-vmarea.cfg /usr/local/sbin/vmarea-first-boot-update /var/lib/cloud/scripts/per-once/10-vmarea-first-boot-update /etc/vmarea/image.conf; do
    grep -qxF "$HDR" "$f" && continue
    if head -1 "$f" | grep -q '^#!'; then
        { head -1 "$f"; echo "$HDR"; tail -n +2 "$f"; } > "$f.new"
    else
        { echo "$HDR"; cat "$f"; } > "$f.new"
    fi
    cat "$f.new" > "$f"
    rm -f "$f.new"
done
{ echo "$HDR"; cat /etc/ssh/sshd_config; } > /etc/ssh/sshd_config.new
mv /etc/ssh/sshd_config.new /etc/ssh/sshd_config
cat > /etc/vmarea/README.txt <<'EOT'
These files let the control panel set your password, hostname and network, and run startup scripts. Removing or changing them can stop those features working. We cannot support servers where they were changed.

/etc/vmarea/README.txt
/etc/vmarea/image.conf
/usr/local/etc/cloud/cloud.cfg.d/90-vmarea.cfg
/usr/local/sbin/vmarea-first-boot-update
/var/lib/cloud/scripts/per-once/10-vmarea-first-boot-update
EOT
