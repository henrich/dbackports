#!/bin/sh
#
# dbackports: Debian Stable Backports tool
# 
# Copyright: 2012, Hideki Yamane <henrich@debian.or.jp/org>
# This program is distributed under GPL-2.0+, see http://spdx.org/licenses/GPL-2.0+
#
# Depends: cowbuilder|pbuilder, devscripts, quilt
# Recommends: sudo
#
# Todo: use git for temporary file handling
#

set -e

usage()
{
        echo  "Usage: dbackports [init|update|build|rollback]"
}


buildtool="cowbuilder"
backports_dir="debian/backports"
patches_dir="$backports_dir"

BPO_T="X-Backports-Target"

if [ ! -f "debian/control" ]; then
    echo "no debian/control exists, aborting..."
    exit 1
else 
    backports_target=`grep "$BPO_T" debian/control` \
      || (echo "no $BPO_T is specified in debian/control, aborting..."; exit 1)
    distribution=`echo $backports_target | cut -d' ' -f2`
fi

if [ -z "$distribution" ]; then
    echo "set approriate $BPO_T (now $distribution) in debian/control, aborting..."
    exit 1
fi

basepath="/var/cache/pbuilder/$distribution.cow"
basetgz="/var/cache/pbuilder/$distribution.tgz"


if [ -f "$HOME"/.dbackports.conf ]; then
    . "$HOME"/.dbackports.conf
fi

# probably there is more efficient way, but it works
if [ ! $USER = root ]; then
    sudo=sudo
fi

if [ ! -z "$MIRRORSITE" ]; then
    mirror="$MIRRORSITE"
else
    mirror="http://cdn.debian.net/debian"
fi

# don't read user's .quiltrc file...
QUILTRC="dont_read_it"
export QUILTRC
export QUILT_SERIES="$PWD/$backports_dir/series"
export QUILT_PATCHES="$backports_dir"

# exclude certain files for quilt
common_exclude="-type f -a  ! -path debian/changelog \
	        -o -path debian/patches -prune -a ! -type d \
	        -o -path debian/backports -prune -a ! -type d" 

# Now we can set environment variables for chroot...
if [ $buildtool = cowbuilder -a -x /usr/sbin/$buildtool ]; then
    chroot_setting="--basepath $basepath --mirror $mirror --distribution $distribution"
elif [ $buildtool = pbuilder -a -x /usr/sbin/$buildtool ]; then
    chroot_setting="--basetgz $basetgz --mirror $mirror --distribution $distribution"
else
    echo "set approriate buildtool (instead of $buildtool), aborting..."
    exit 1
fi

case "$1" in
  init)
    if [ $buildtool = cowbuilder -a ! -d "$basepath" ]; then
	echo "Initialize stable $buildtool environment."
	$sudo $buildtool --create $chroot_setting    
    elif [ $buildtool = pbuilder -a ! -f "$basetgz" ]; then
	echo "Initialize stable $buildtool environment."
	$sudo $buildtool --create $chroot_setting    
    fi

# dch only support Debian stable backports?
    if [ ! -d "$backports_dir" ]; then
        mkdir $backports_dir && \
        find debian $common_exclude | cpio -pdV --quiet $backports_dir && 
            echo debian/changelog | cpio -pdV --quiet $backports_dir &&\
            mv $backports_dir/debian/changelog $backports_dir/changelog && \
            dch --bpo --changelog $backports_dir/changelog \
              -m "For detail of changes, see $backports_dir/$distribution"
        if [ -d .pc ]; then
            mv .pc $backports_dir/orig.pc
        fi
          quilt new $distribution > /dev/null && \
          for file in `find debian $common_exclude` 
          do
            quilt add -P "$distribution" $file 2>&1 >/dev/null
          done && \
        date +%s > $backports_dir/timestamp && \
        echo "Ready."
        echo " "
    else
        echo "It seems that already there is $backports_dir directory, nothing to do."
        echo "Ready."
        echo " "
    fi
  ;;

  up|update)
    update_files=`find debian -newer $backports_dir/timestamp $common_exclude`
    for update_file in $update_files
    do
        if [ ! -f $backports_dir/$update_file ]; then
             quilt add -P "$distribution" $update_file
        fi
    done
    quilt refresh 2>&1 >/dev/null 

    get_version=`dpkg-parsechangelog -c1 | grep ^Version |cut -d' ' -f2`
    (echo "$get_version" | grep "bpo" &&  \
      dch -i --changelog $backports_dir/changelog  -m "update backports.") || \
      dch -e --changelog $backports_dir/changelog -D "$distribution"-backports \
        -m "For detail of changes, see debian/backports/$distribution"

    cp -ap "debian/changelog" "debian/changelog_original" && \
    cp -ap "$backports_dir/changelog" "debian/changelog" && \
    dpkg-buildpackage -S -us -uc > /dev/null

    echo " "
    echo "Now here's a backports patch in $backports_dir/$distribution and its source."
    echo "Ready to build (or "dbackports back")."
    echo " "
  ;;

  rollback)
    if [ -f debian/changelog_original ]; then
        cp -ap debian/changelog_original debian/changelog && rm debian/changelog_original
    fi

    if [ -d "$backports_dir/orig.pc" ]; then
        rm -rf .pc && \
        cp -arp $backports_dir/orig.pc .pc && rm -r "$backports_dir/orig.pc"
    fi

    if [ -d $backports_dir ]; then
        rm -rf $backports_dir
    fi
  ;;

  build)
    package_name=`dpkg-parsechangelog -l$backports_dir/changelog|grep ^Source |cut -d' ' -f2`
    bpo_version=`dpkg-parsechangelog -c1 | grep ^Version |cut -d' ' -f2 | grep bpo`

# it woundn't work...
    if [ "$bpo_version" = \d+:* ]; then
        bpo_version =`echo $bpo_version | cut -d':' -f2`
    fi

    $sudo $buildtool --build ../"$package_name"_"$bpo_version".dsc $chroot_setting
  ;;

  *)
    echo "please specify option."
    usage
  ;;

esac

exit 0
