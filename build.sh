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
apt-get install -y -q qemu-user-static curl unzip zip

#
# Input files
#
ZIP=2020-12-02-raspios-buster-armhf.zip
IMG=2020-12-02-raspios-buster-armhf.img
LOOP=/dev/loop7
LOOPpart=/dev/loop7p2
# download the OS image file as zip 
if [ ! -e $ZIP ] ; then
	curl -L -O https://downloads.raspberrypi.org/raspios_armhf/images/raspios_armhf-2020-12-04/$ZIP
fi

#... and unzip
if [ ! -e $IMG ] ; then
	unzip $ZIP
fi
if [ ! -e carbidemotion-522.deb ] ; then
	curl -O -L http://carbide3d.com/dl/pi/carbidemotion-522.deb
fi

# we need the loopback devices to support partitioned devices, so force this on
modprobe loop max_part=31

# cleanup in case a previous run aborted

umount -l image &> /dev/null
rmdir image &> /dev/null
losetup -d $LOOP


# set up the file as a loopback device, so that we can mount it
losetup $LOOP $IMG
# scan it for partitions, since it's a full disk image with a partition table, not just a bare image
partx $LOOP
# mont partition 2 (partition 1 is the bootloder
mkdir image &> /dev/null
mount $LOOPpart image
# we need "qmu-arm-static in the image for the chroots below to work

cp /usr/bin/qemu-arm-static image/usr/bin/

# copy the carbide motion file into the image
mkdir -p image/tmp/discard
cp carbidemotion-522.deb image/tmp/discard

# workaround, pypy refuses to remove in a chroot 

echo "#!/bin/sh" > image/var/lib/dpkg/info/pypy.prerm
echo "exit 0" >> image/var/lib/dpkg/info/pypy.prerm
chmod a+x image/var/lib/dpkg/info/pypy.prerm


#
# Add some key software we want in the image

# usbmount will let us auto mount USB sticks
chroot image apt-get install -y usbmount udisks2

# Samba for network shares
DEBIAN_FRONTEND=noninteractive chroot image apt-get install -y --assume-yes samba
# and some things we don't want auto-removes
chroot image apt-mark manual udisks2 samba

#
# Remove some extra software not needed for a CNC controller
# we do this in three steps to recursively remove these, as well as their configuration leftovers
#
LIST="chromium-codecs-ffmpeg-extra ffmpeg chromium-browser chromium-browser-l10n vlc alacarte dillo fio geany geany-common gpicview libass9 libavcodec58 libavfilter7 libavformat58 libavresample4 libavutil56 libbluray2 libcodec2-0.8.1 vlc-plugin-base vlc-plugin-*  thonny rpi-chromium-mods realvnc-vnc-server libmp3lame0 gcc-8 cups manpages-dev libc6-dev tk8.6-blt2.5  pypy cups-daemon git gsfonts  ghostscript libjs-sphinxdoc libjs-jquery libjs-underscore libraspberrypi-doc rpd-wallpaper libc6-dbg poppler-data poppler-utils libsane libpoppler82 python-numpy cups-common"

chroot image apt autoremove -q -y $LIST
chroot image apt purge -q -y $LIST
chroot image apt autoremove -q -y


rm -rf image/usr/lib/pypy/

# Install carbide motion
#

chroot image/ apt-get install -q -y /tmp/discard/carbidemotion-522.deb 





# clean the download cache
chroot image apt-get clean

# final configuration, autostart CM
cp image/usr/share/applications/carbidemotion.desktop image/etc/xdg/autostart

#
# reporting and cleanup
#
chroot image dpkg --list > list
rm -f image/tmp/discard/*deb
rm -f image/usr/bin/qemu-arm-static
rmdir image/tmp/discard


#
# Now that we're done with the content of the image, time to optimize it for burning/etc
#

#
# Resize FS tricks; this moves all content to the beginning of the image
#
umount image
e2fsck -f $LOOPpart
resize2fs -M $LOOPpart
resize2fs $LOOPpart
mount $LOOPpart image

#
# zero out any empty space in the filesystem so that it zips up well
#
dd if=/dev/zero of=image/tmp/full &> /dev/null
rm -f image/tmp/full 

# and unmount / remove the loop device

if [ ! -e KEEP ] ; then
	umount image
	sync
	losetup -d $LOOP
	zip -9 rpi-carbidemotion.zip $IMG
fi
