#!/bin/sh
rm -f /etc/ssh/ssh_host_* /etc/hostid
: > /etc/resolv.conf
rm -rf /root/.ssh /root/.history /tmp/* /var/tmp/* /var/cache/nuageinit /var/lib/cloud/instance /var/lib/cloud/instances /var/lib/cloud/data /var/lib/cloud/sem /var/lib/cloud/seed /var/lib/cloud/handlers
find /var/log -type f -exec truncate -s 0 {} +
touch /firstboot
dd if=/dev/zero of=/zerofill bs=1m 2>/dev/null
rm -f /zerofill
sync
nohup sh -c 'sleep 2; shutdown -p now' >/dev/null 2>&1 &
