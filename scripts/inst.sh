

base=`dirname $0`
base=`realpath "$base"`
logfile=$base/inst.log
[ -f $logfile ] && mv $logfile $base/prev-inst.$$.log
exec 3>&1 1>${logfile} 2>&1

srcdev=`mount | grep " / " | cut -d ' ' -f 1`

matching_3000="23438819328 sectors" # 3000 install disk
matching_1000="5860533168 sectors" # 1000 install disk

# find a disk that has the matching size
disks_3000=( `fdisk -l | grep  "$matching_3000" | cut -d " " -f 2 | cut -d : -f 1` )
disks_1000=( `fdisk -l | grep  "$matching_1000" | cut -d " " -f 2 | cut -d : -f 1` )
echo "Install disk matching 3000 $matching_3000 found: $disks_3000" 1>&3
echo "Install disk matching 1000 $matching_1000 found: $disks_1000" 1>&3
if [ ${#disks_3000[@]} == 1 ]; then
        ISP="3000"
	dstdev=${disks_3000[0]}
	boot_start=2048s
	boot_end=1026047s
	golden_start=1026048s
	golden_end=5220351s
	lvm_start=5220352s
	lvm_end=23438819294s
	root_size=419430400S
	swap_size=66076672S
	home_size=11166916608S
	bglog_size=10942308352S
elif [ ${#disks_1000[@]} == 1 ]; then
        ISP="1000"
	dstdev=${disks_1000[0]}
	boot_start=2048s
	boot_end=1026047s
	golden_start=1026048s
	golden_end=5220351s
	lvm_start=1026048s
	lvm_end=5860532223s
	root_size=21504000S
	swap_size=66076672S
	home_size=2662400000S
	bglog_size=2916524032S
else
    echo "can not find exactly one disk mathching 3000 or 1000" 1>&3
    exit
fi

echo "installing on $dstdev from $srcdev" 1>&3

bootdev="$dstdev"1
goldev="$dstdev"2
lvmdev="$dstdev"3
vg=VolGroup

#Name of the logical volume name
lv_root=lv_root
lv_swap=lv_swap
lv_home=lv_home
lv_bglog=lv_bglog

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

parted -s $dstdev mklabel gpt
parted  $dstdev <<EOF
unit s
mkpart  primary ext4 $boot_start $boot_end
mkpart  primary ext4 $golden_start $golden_end
mkpart	primary $lvm_start $lvm_end
set 3 lvm on
set 2 boot on
p
EOF

echo "creating boot filesystem on $bootdev" 1>&3
mkfs.ext4 -F -F -O "^64bit" $bootdev
e2label $bootdev /boot

mkfs.ext4 -F -F -O "^64bit" $goldev
e2label $goldev golden

echo "installing golden partition" 1>&3
[ ! -d /img ] && mkdir /img
mount $goldev /img

[ ! -d /src ] && mkdir /src
mount $srcdev /src
cp -ra /src/{bin,boot,dev,etc,home,lib,lib64,mnt,opt,proc,root,run,sbin,srv,sys,tmp,usr,var} /img

# need to update fstab due to uuid change
cat > /img/etc/fstab <<EOF
LABEL=golden	/         	ext4      	rw,relatime,data=ordered	0 1

EOF

echo "installing golden bootloader" 1>&3
extlinux -i /img/boot/syslinux
umount /src
umount /img

echo "creating volume group $vg" 1>&3
pvcreate -ff -y $lvmdev
pvs --unit s
vgcreate $vg $lvmdev
vgs --unit s

lvcreate  -y -L $root_size -n $lv_root $vg
lvcreate  -y -L $swap_size -n $lv_swap $vg
lvcreate  -y -L $home_size -n $lv_home $vg
lvcreate  -y -L $bglog_size -n $lv_bglog $vg
lvs --unit s
vgs --unit s

echo "creating file system inside volume group $vg" 1>&3
mkfs.ext4 -F -F -O "^64bit"  /dev/mapper/$vg-$lv_root

mkswap /dev/mapper/$vg-$lv_swap
mkfs.ext4  -F -F -O "^64bit" /dev/mapper/$vg-$lv_home
mkfs.ext4  -F -F -O "^64bit" /dev/mapper/$vg-$lv_bglog

echo "installing system files" 1>&3
[ ! -d /img ] && mkdir /img
mount /dev/mapper/$vg-$lv_root /img
[ ! -d /img/boot ] && mkdir /img/boot
mount $bootdev /img/boot
time pv $base/$rootarch 2>&3 | $base/tar --selinux -zxf - -C /img
umount /img/boot
touch /img/root/factory_flag
cp -fr $base/rc.local /img/etc/ 
cp -fr $base/update_dev_id.sh /img/usr/local/bin
mkdir /img/root/network_config
cp -fr $base/network_config/ifcfg-* /img/root/network_config
cp -fr $base/network_config/cover.sh /img/root/network_config
if [ "$ISP" == "1000" ]; then
    cp -fr $base/network_config/change_network_1000.sh /img/root/network_config/change_network.sh
    cp -fr $base/network_config/restart_udev_1000.sh /img/root/network_config/restart_udev.sh
else
    cp -fr $base/network_config/change_network_3000.sh /img/root/network_config/change_network.sh
    cp -fr $base/network_config/restart_udev_3000.sh /img/root/network_config/restart_udev.sh
fi

echo "instaling home partition" 1>&3
[ ! -d /home ] && mkdir /home
mount /dev/mapper/$vg-$lv_home /home
$base/tar --selinux -zxf $base/$homearch -C /home

echo "installing bglog partition" 1>&3
[ ! -d /bglog ] && mkdir /bglog
mount /dev/mapper/$vg-$lv_bglog /bglog
mkdir -p /bglog/BGdata
mkdir -p /bglog/sub_node.ext

echo "installing bootloader" 1>&3
mount -t proc proc /img/proc
mount -o bind /dev /img/dev
mount -t sysfs sys /img/sys
mount -o bind /dev/pts /img/dev/pts

##chroot /img /usr/sbin/grub2-install --boot-directory=/boot $dstdev
chroot /img/ /bin/env PATH=/bin:/usr/bin:/sbin:/usr/sbin /bin/mount $bootdev /boot
cp /img/boot/grub/device.map /tmp/device.map
echo "# this device map was generated by inst.sh" > /img/boot/grub/device.map
echo "(hd0)    $dstdev" >> /img/boot/grub/device.map
cat /img/boot/grub/device.map
chroot /img  /bin/env PATH=/bin:/usr/bin:/sbin:/usr/sbin /sbin/grub-install $dstdev
cp -f /tmp/device.map /img/boot/grub/device.map
cp /boot/vmlinuz-linux /boot/initramfs-linux-fallback.img  /boot/initramfs-linux.img /img/boot
cat >>/img/boot/grub/grub.conf <<EOF
title Golden
	root (hd0,0)
	kernel /vmlinuz-linux root=LABEL=golden
	initrd /initramfs-linux.img
EOF


echo "umounting file systems and flushing cache to disk" 1>&3
umount $bootdev
umount /img/dev/pts
umount /img/dev
umount /img/sys
umount /img/proc
umount /img
umount /home
umount /bglog

echo "taking factory snapshot" 1>&3
lvcreate -y -L 200G -s -n $lv_root.factory $vg/$lv_root
#lvcreate -y -L 1024000S -n lv_boot $vg
#partclone.ext4 -b -s $bootdev -o /dev/$vg/lv_boot
#e2label /dev/$vg/lv_boot /boot.mirror
#lvcreate -y -L 200M -s -n lv_boot.factory $vg/lv_boot

echo "install on $dstdev done" 1>&3
vgchange -an $vg

