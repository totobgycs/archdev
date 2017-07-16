#!/usr/bin/env bash
# Generate a minimal filesystem for archlinux and load it into the local
# docker as "totobgycs/archdev"
# based on https://github.com/docker/docker/blob/master/contrib/mkimage-arch.sh
# requires root
set -e

hash pacstrap &>/dev/null || {
	echo "Could not find pacstrap. Run pacman -S arch-install-scripts"
	exit 1
}

hash expect &>/dev/null || {
	echo "Could not find expect. Run pacman -S expect"
	exit 1
}

ROOTFS=$(mktemp -d ${TMPDIR:-/var/tmp}/rootfs-archlinux-XXXXXXXXXX)
chmod 755 $ROOTFS

# packages to ignore for space savings
PKGIGNORE=(
    cryptsetup
    device-mapper
    dhcpcd
    iproute2
    jfsutils
    linux
    lvm2
    man-db
    man-pages
    mdadm
    netctl
    openresolv
    pciutils
    pcmciautils
    reiserfsprogs
    s-nail
    systemd-sysvcompat
    usbutils
    vi
    xfsprogs
)
IFS=','
PKGIGNORE="${PKGIGNORE[*]}"
unset IFS

expect <<EOF
	set send_slow {1 .1}
	proc send {ignore arg} {
		sleep .1
		exp_send -s -- \$arg
	}
	set timeout 300

	spawn pacstrap -C ./mkimage-arch-pacman.conf -c -d -G -i $ROOTFS base base-devel git wget haveged yajl --ignore $PKGIGNORE
	expect {
		-exact "anyway? \[Y/n\] " { send -- "n\r"; exp_continue }
		-exact "(default=all): " { send -- "\r"; exp_continue }
		-exact "installation? \[Y/n\]" { send -- "y\r"; exp_continue }
	}
EOF

rm -r $ROOTFS/usr/share/man/*
rm $ROOTFS/etc/pacman.d/mirrorlist
echo "Server = https://archlinux.surlyjake.com/archlinux/$repo/os/$arch" > $ROOTFS/etc/pacman.d/mirrorlist
echo "Server = http://mirrors.evowise.com/archlinux/$repo/os/$arch" >> $ROOTFS/etc/pacman.d/mirrorlist
echo "Server = http://mirror.rackspace.com/archlinux/$repo/os/$arch" >> $ROOTFS/etc/pacman.d/mirrorlist
echo "Server = http://arch.apt-get.eu/$repo/os/$arch" >> $ROOTFS/etc/pacman.d/mirrorlist

arch-chroot $ROOTFS /bin/sh -c "haveged -w 1024; pacman-key --init; pkill haveged;pacman -Rs --noconfirm haveged"
arch-chroot $ROOTFS /bin/sh -c "pacman-key --populate archlinux; pkill gpg-agent"

echo 'Add user build'
arch-chroot $ROOTFS /bin/sh -c 'useradd -m build'
echo 'build ALL=(ALL) NOPASSWD: ALL' >> $ROOTFS/etc/sudoers
echo 'Install package-query'
arch-chroot $ROOTFS /bin/sh -c 'cd /home/build \
	&& curl https://aur.archlinux.org/cgit/aur.git/snapshot/package-query.tar.gz -0 | tar -zx \
	&& chown -R build:build package-query \
	&& cd package-query \
	&& sudo -u build makepkg -si --noconfirm \
	&& cd .. \
	&& rm -rf package-query \
	&& curl https://aur.archlinux.org/cgit/aur.git/snapshot/yaourt.tar.gz -0 | tar -zx \
	&& chown -R build:build yaourt \
	&& cd yaourt \
	&& sudo -u build makepkg -si --noconfirm \
	&& cd .. \
	&& rm -rf yaourt'
	
echo 'en_US.UTF-8 UTF-8' > $ROOTFS/etc/locale.gen
echo 'hu_HU.UTF-8 UTF-8' >> $ROOTFS/etc/locale.gen
echo 'nl_NL.UTF-8 UTF-8' >> $ROOTFS/etc/locale.gen
echo 'ro_RO.UTF-8 UTF-8' >> $ROOTFS/etc/locale.gen
echo 'de_DE.UTF-8 UTF-8' >> $ROOTFS/etc/locale.gen
arch-chroot $ROOTFS locale-gen
arch-chroot $ROOTFS /bin/sh -c 'yes | yaourt -Scc'

# udev doesn't work in containers, rebuild /dev
DEV=$ROOTFS/dev
rm -rf $DEV
mkdir -p $DEV
mknod -m 666 $DEV/null c 1 3
mknod -m 666 $DEV/zero c 1 5
mknod -m 666 $DEV/random c 1 8
mknod -m 666 $DEV/urandom c 1 9
mkdir -m 755 $DEV/pts
mkdir -m 1777 $DEV/shm
mknod -m 666 $DEV/tty c 5 0
mknod -m 600 $DEV/console c 5 1
mknod -m 666 $DEV/tty0 c 4 0
mknod -m 666 $DEV/full c 1 7
mknod -m 600 $DEV/initctl p
mknod -m 666 $DEV/ptmx c 5 2
ln -sf /proc/self/fd $DEV/fd

tar --numeric-owner --xattrs --acls -C $ROOTFS -c . | docker import - totobgycs/archdev
docker run -t totobgycs/archdev echo Success.
rm -rf $ROOTFS
