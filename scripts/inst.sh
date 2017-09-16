

logfile=/tmp/inst.log
exec 3>&1 1>${logfile} 2>&1

base=`dirname $0`
base=`realpath "$base"`

matching="931 GiB"
# find a disk that has the matching size
disks=( `fdisk -l | grep  "$matching" | cut -d " " -f 2 | cut -d : -f 1` )
echo "Install disk matching $matching found: $disks" 1>&3
if [ ${#disks[@]} != 1 ]; then
    echo "can not find exactly one disk mathching $matching : $disks" 1>&3
    exit
fi

dstdev=${disks[0]}
echo "installing on $dstdev" 1>&3

boot="$dstdev"1
lvm="$dstdev"2
vg=VolGroup
lvsize=860160000S
swsize=66076672S 
#bootarch=boot.tar.bz2
rootarch=lvroot-selinux.tar.gz
homearch=lvhome-selinux.tar.gz
mbr=sda.mbr.dd

echo base is $base

#vgchange -an $vg
vgchange -an 

# for tar --selinux
ln -sf $base/libselinux.so.1 /lib64

echo "creating partition on $dstdev" 1>&3
# empty the GTP label
dd if=$base/$mbr of=$dstdev

parted -s $dstdev mklabel msdos
parted  $dstdev <<EOF
mkpart  primary ext4 2048s 1026047s 
mkpart	primary 1026048s  1952448511s
set 2 lvm on
unit s
p
EOF

echo "creating boot filesystem on $boot" 1>&3
# empty the GTP label
mkfs.ext4 -F -F -O "^64bit" $boot
e2label $boot /boot

echo "creating volume group $vg" 1>&3
pvcreate -ff -y $lvm
pvs --unit s
vgcreate $vg $lvm
vgs --unit s
lvcreate  -y -L $lvsize -n lv_root $vg
lvcreate  -y -L $swsize -n lv_swap $vg
lvcreate  -y -L 127205376S -n lv_home $vg
lvcreate  -y -L 184352768S -n lv_bglog $vg
lvs --unit s


echo "creating file system inside volume group $vg" 1>&3
mkfs.ext4 -F -F -O "^64bit"  /dev/mapper/$vg-lv_root

mkswap /dev/mapper/$vg-lv_swap
mkfs.ext4  -F -F -O "^64bit" /dev/mapper/$vg-lv_home
mkfs.ext4  -F -F -O "^64bit" /dev/mapper/$vg-lv_bglog

echo "installing system files" 1>&3
[ ! -d /img ] && mkdir /img
mount /dev/mapper/$vg-lv_root /img
[ ! -d /img/boot ] && mkdir /img/boot
mount $boot /img/boot
pv $base/$rootarch 2>&3 | $base/tar --selinux -zxf - -C /img
umount /img/boot
touch /img/root/factory_flag
cp -fr $base/rc.local /img/etc/ 
cp -fr $base/update_dev_id.sh /img/usr/local/bin
cp -fr $base/network_config /img/root


echo "instaling home partition" 1>&3
[ ! -d /home ] && mkdir /home
mount /dev/mapper/$vg-lv_home /home
$base/tar --selinux -zxf $base/$homearch -C /home

echo "installing bglog partition" 1>&3
[ ! -d /bglog ] && mkdir /bglog
mount /dev/mapper/$vg-lv_bglog /bglog
mkdir -p /bglog/BGdata
mkdir -p /bglog/sub_node.ext

echo "installing bootloader" 1>&3
mount -t proc proc /img/proc
mount -o bind /dev /img/dev
mount -t sysfs sys /img/sys
mount -o bind /dev/pts /img/dev/pts

##chroot /img /usr/sbin/grub2-install --boot-directory=/boot $dstdev
chroot /img/ /bin/env PATH=/bin:/usr/bin:/sbin:/usr/sbin /bin/mount $boot /boot

echo "# this device map was generated by inst.sh" > /img/boot/grub/device.map
echo "(hd0)    $dstdev" >> /img/boot/grub/device.map
cat /img/boot/grub/device.map
chroot /img  /bin/env PATH=/bin:/usr/bin:/sbin:/usr/sbin /sbin/grub-install $dstdev

# need to update fstab due to uuid change

echo "umounting file systems and flushing cache to disk" 1>&3
umount $boot
umount /img/dev/pts
umount /img/dev
umount /img/sys
umount /img/proc
umount /img
umount /home
umount /bglog

echo "taking factory snapshot" 1>&3
lvcreate -y -L 10G -s -n lv_root.factory $vg/lv_root
lvcreate -y -L 1024000S -n lv_boot $vg
partclone.ext4 -b -s $boot -o /dev/$vg/lv_boot
lvcreate -y -L 200M -s -n lv_boot.factory $vg/lv_boot

echo "install on $dstdev done" 1>&3
vgchange -an $vg

