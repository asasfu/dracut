#!/bin/sh
# don't let udev and this script step on eachother's toes
set -x
for x in 64-lvm.rules 70-mdadm.rules 99-mount-rules; do
    > "/etc/udev/rules.d/$x"
done
udevadm control --reload-rules
# save a partition at the beginning for future flagging purposes
sfdisk -C 1280 -H 2 -S 32 -L /dev/sda <<EOF
,16
,400
,400
,400
EOF
echo -n test >keyfile
cryptsetup -q luksFormat /dev/sda2 /keyfile
cryptsetup -q luksFormat /dev/sda3 /keyfile
cryptsetup -q luksFormat /dev/sda4 /keyfile
cryptsetup luksOpen /dev/sda2 dracut_sda2 </keyfile
cryptsetup luksOpen /dev/sda3 dracut_sda3 </keyfile 
cryptsetup luksOpen /dev/sda4 dracut_sda4 </keyfile
mdadm --create /dev/md0 --run --auto=yes --level=5 --raid-devices=3 /dev/mapper/dracut_sda2 /dev/mapper/dracut_sda3 /dev/mapper/dracut_sda4
# wait for the array to finish initailizing, otherwise this sometimes fails
# randomly.
mdadm -W /dev/md0
lvm pvcreate -ff  -y /dev/md0 && \
lvm vgcreate dracut /dev/md0 && \
lvm lvcreate -l 100%FREE -n root dracut && \
lvm vgchange -ay && \
mke2fs /dev/dracut/root && \
mkdir -p /sysroot && \
mount /dev/dracut/root /sysroot && \
cp -a -t /sysroot /source/* && \
umount /sysroot && \
lvm lvchange -a n /dev/dracut/root && \
lvm vgchange -a n dracut && \
{
lvm vgdisplay  && \
{ mdadm -W /dev/md0 || :;} && \
mdadm --stop /dev/md0 && \
cryptsetup luksClose /dev/mapper/dracut_sda2 && \
cryptsetup luksClose /dev/mapper/dracut_sda3 && \
cryptsetup luksClose /dev/mapper/dracut_sda4 && \
:; :;} && \
echo "dracut-root-block-created" >/dev/sda1
poweroff -f