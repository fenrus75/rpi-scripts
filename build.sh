#!/bin/bash


#
# This script downloads (and caches) a raspberry pi OS image and does some basic modifications to it.
# RIght now, this script needs root privileges (sorry; WIP) and kind of assumes to run on a Debian
# based Linux OS... it can run on x86 just fine (it will use qemu to emulate running ARM binaries
# when needed) but should also work on the Raspberry PI itself.
#

#
# This script needs qemu-user-static (to run ARM binaries on x86) as well as curl and zip/unzip
#
apt-get install -y -q qemu-user-static curl unzip zip parted coreutils hardlink

#
# Input files
#
ZIP=2020-12-02-raspios-buster-armhf.zip
IMG=2020-12-02-raspios-buster-armhf.img
IMG2=rpi-carbidemotion.img
LOOP=/dev/loop7
LOOPpart=/dev/loop7p2
# download the OS image file as zip 
if [ ! -e $ZIP ] ; then
	curl -L -O https://motion-pi.us-east-1.linodeobjects.com/carbidemotion-524.deb
fi

#... and unzip
if [ ! -e $IMG ] ; then
	unzip $ZIP
fi


if [ ! -e carbidemotion-524.deb ] ; then
	curl -O -L https://motion-pi.us-east-1.linodeobjects.com/carbidemotion-524.deb
fi

# we need the loopback devices to support partitioned devices, so force this on
modprobe loop max_part=31

# cleanup in case a previous run aborted

umount -l image &> /dev/null
rmdir image &> /dev/null
losetup -d $LOOP

# work on a copy of the img file so that we can restart prestine each time without having to unzip

if [ ! -e KEEP ] ; then
	cp $IMG $IMG2
fi

if [ ! -e $IMG2 ] ; then
	cp $IMG $IMG2
fi


# set up the file as a loopback device, so that we can mount it
losetup $LOOP $IMG2
# scan it for partitions, since it's a full disk image with a partition table, not just a bare image
partx $LOOP
# mont partition 2 (partition 1 is the bootloder
mkdir image &> /dev/null
mount $LOOPpart image
# we need "qmu-arm-static in the image for the chroots below to work

cp /usr/bin/qemu-arm-static image/usr/bin/

# copy the carbide motion file into the image
mkdir -p image/tmp/discard
cp carbidemotion-524.deb image/tmp/discard

#
# Delayed launcher so that CM does not start until the user is done configuring
# This invokes GCC inside the image, so needs to be done before GCC is removed
# below
#
cp launch-cm.c image/tmp/
chroot image gcc -O2 -Wall tmp/launch-cm.c -o /usr/bin/launch-cm
rm image/tmp/launch-cm.c


# workaround, pypy refuses to remove in a chroot 

echo "#!/bin/sh" > image/var/lib/dpkg/info/pypy.prerm
echo "exit 0" >> image/var/lib/dpkg/info/pypy.prerm
chmod a+x image/var/lib/dpkg/info/pypy.prerm


#
# Add some key software we want in the image

# usbmount will let us auto mount USB sticks
chroot image apt-get install -y usbmount
# wmctrl lets us make an application full screen
chroot image apt-get install -y wmctrl

# Samba for network shares
DEBIAN_FRONTEND=noninteractive chroot image apt-get install -y --assume-yes samba
# and mark some things we don't want auto-removed
chroot image apt-mark manual samba

#
# Install carbide motion
#
chroot image/ apt-get install -q -y /tmp/discard/carbidemotion-524.deb 


#
# Remove some extra software not needed for a CNC controller
# we do this in three steps to recursively remove these, as well as their configuration leftovers

BROWSERS="chromium-browser chromium-browser-l10n dillo rpi-chromium-mods "
CODECS="chromium-codecs-ffmpeg-extra ffmpeg vlc libavcodec58 libavfilter7 libavformat58 libavresample4 libavutil56 libbluray2 libcodec2-0.8.1 vlc-plugin-base vlc-plugin-* libmp3lame0  "
PRINTING="cups gsfonts  ghostscript cups-daemon cups-common  poppler-data poppler-utils  libpoppler82 libsane cups-pk-helper system-config-printer avahi-daemon system-config-printer-common python3-cupshelpers"
DEVTOOLS="fio gcc-8 manpages-dev libc6-dev tk8.6-blt2.5 git libc6-dbg libjs-sphinxdoc libjs-jquery libjs-underscore libraspberrypi-doc gdb dmidecode gdbm-l10n pkg-config luajit dpkg-dev "
PYTHONMISC="pypy python-numpy python3-crypto python-setuptools python3-setuptools python3-gi python-cryptography python3-cryptography python3-psutil python-gi python3-picamera python-chardet python3-chardet python3-apt python3-pkg-resources python-pkg-resources"
GUIMISC="geany geany-common gpicview realvnc-vnc-server rpd-wallpaper scrot giblib1 gtk2-engines-clearlookspix gui-pkinst libmikmod3 plymouth rpd-plym-splash v4l-utils timgm6mb-soundfont "
DOCS="debian-reference-common debian-reference-en rp-bookshelf"
#
LIST="$CODECS $BROWSERS $DEVTOOLS $PRINTING $PYTHONMISC $GUIMISC $DOCS alacarte libass9 thonny   "

chroot image apt autoremove -q -y $LIST
chroot image apt purge -q -y $LIST
chroot image apt autoremove -q -y


rm -rf image/usr/lib/pypy/

#
# And now we add back "arandr" since some weird displays need it
#
chroot image/ apt-get install -q -y arandr


#
# Install carbide motion
#
chroot image/ apt-get install -q -y /tmp/discard/carbidemotion-524.deb 



# final configuration, 


# autostart CM
cp carbidemotion.desktop image/etc/xdg/autostart

# rc.local bootup script replacement
cp rc.local image/etc/rc.local

# clean the download cache
chroot image apt-get clean

# samba config
cp smb.conf image/etc/samba/smb.conf
mkdir -p image/gcode/usb
chown 1000.1000 image/gcode
chroot image systemctl enable smbd

# mount namespace so that automounting of USB sticks works

mkdir -p image/etc/systemd/system/systemd-udevd.service.d/
echo "[Service]" > image/etc/systemd/system/systemd-udevd.service.d/myoverride.conf
echo "MountFlags=shared" >> image/etc/systemd/system/systemd-udevd.service.d/myoverride.conf
echo "PrivateMounts=no" >> image/etc/systemd/system/systemd-udevd.service.d/myoverride.conf

# redirect the first USB stick to /gode/usb
echo "/dev/sda1        /gcode/usb   vfat	user,noauto,uid=1000     0       0" >> image/etc/fstab

#
# reporting and cleanup
#
chroot image dpkg --list > list
rm -f image/tmp/discard/*deb
rm -f image/usr/bin/qemu-arm-static
rm -f image/home/pi/Bookshelf/000_RPi_BeginnersGuide_DIGITAL.pdf
rmdir image/tmp/discard

#
# Reporting package dependencies
#
chroot image ldd /usr/local/bin/carbidemotion  | cut -f3 -d" " > cm-libdeps
for i in `cat cm-libdeps`; do chroot image dpkg -S /usr/$i ; done > cm-pkgdeps


#
# Hardlink identical files
#
pushd image
hardlink -X .
popd

#
# zero out any empty space in the filesystem so that it zips up well
#
dd if=/dev/zero of=image/tmp/full &> /dev/null
rm -f image/tmp/full 


#
# Now that we're done with the content of the image, time to optimize it for burning/etc
#

#
# Resize FS tricks; this moves all content to the beginning of the image
#
if [ ! -e NOSHRINK ]; then
	umount image
	e2fsck -f $LOOPpart
	# shrink the FS to the minimum size
	resize2fs -M $LOOPpart
	# adjust the partition table
	yes | parted ---pretend-input-tty $LOOP resizepart 2 2400M
	# stop the loop device
	losetup -d $LOOP
	# reduce the size of the file
	truncate $IMG2 --size 2450M
	# and re-establish the devices/mount point
	losetup $LOOP $IMG2
	partx $LOOP
	# fill the whole partition
	resize2fs $LOOPpart
	mount $LOOPpart image
fi

#
# zero out (again) any empty space in the filesystem so that it zips up well
#
dd if=/dev/zero of=image/tmp/full &> /dev/null
rm -f image/tmp/full 

# and unmount / remove the loop device

if [ ! -e KEEP ] ; then
	umount image
	sync
	losetup -d $LOOP
	zip -9 rpi-carbidemotion.zip $IMG2
fi
