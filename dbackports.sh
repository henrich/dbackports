#!/bin/sh
#
# dbackports: Debian Stable Backports tool
# 
# Copyright: 2012, Hideki Yamane <henrich@debian.or.jp/org>
# This program is distributed under GPL-2.0+, see http://spdx.org/licenses/GPL-2.0+
#
# Todo: able to use cowbuilder, too.
#       now it's pbuilder specific setting, some people want to use cowbuilder instead.
#       
# Depends: cowbuilder|pbuilder, devscripts, quilt
# Recommends: sudo

set -e

buildtool="cowbuilder"
basepath="/var/cache/pbuilder/$distribution.cow"
basetgz="/var/cache/pbuilder/$distribution.tgz"

backports_dir="debian/backports"
patches_dir="$backports_dir"

if [ -f "$HOME"/.dbackports.conf ]; then
    . "$HOME"/.dbackports.conf
fi

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
common_exclude="find debian -type f -a  ! -path debian/changelog \
	                    -o -path debian/patches -prune -a ! -type d \
	                    -o -path debian/backports -prune -a ! -type d" 

# Now we can set environment variables for chroot...
if [ $buildtool = cowbuilder ]; then
    chroot_setting="--basepath $basepath --mirror $mirror --distribution $distribution"
elif [ $buildtool = pbuilder ]; then
    chroot_setting="--basetgz $basetgz --mirror $mirror --distribution $distribution"
else
    echo "set approriate buildtool (not $buildtool), aborting..."
    exit 1
fi

case "$1" in
  init)
    if [ $buildtool = cowbuilder -a ! -f "$basepath"]; then
	echo "Initialize stable $buildtool environment."
	$sudo $buildtool --create $chroot_setting    
    elif [ $buildtool = pbuilder -a ! -f "$basetgz" ]; then
	echo "Initialize stable $buildtool environment."
	$sudo $buildtool --create $chroot_setting    
    fi

# dch only support Debian stable backports?
    if [ ! -d "$backports_dir" ]; then
        mkdir $backports_dir && \
        find debian $common_exclude | cpio -pdV --quiet $backports_dir && \
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
    update_files=`find debian $common_exclude -a -newer $backports_dir/timestamp`

    if [ ! -z "$update_files" ]; then
         quilt add -P "$distribution" "$update_files" && date +%s > $backports_dir/timestamp
    else
        echo "No changes are applied yet."
        exit 1
    fi

    quilt refresh 2>&1 >/dev/null && rm -r .pc/$distribution

    if [ -e $backports_dir/debian ]; then
        rm -rf $backports_dir/debian
    fi


    get_version=`dpkg-parsechangelog -c1 | grep ^Version |cut -d' ' -f2`

    (echo "$get_version" | grep "bpo" &&  \
      dch -i --changelog $backports_dir/changelog  -m "update backports.") || \
      dch -e --changelog $backports_dir/changelog -D "$distribution"-backports \
        -m "For detail of changes, see debian/backports/$distribution"

    package_name=`dpkg-parsechangelog -l$backports_dir/changelog|grep ^Source |cut -d' ' -f2`

    cp -ap "debian/changelog" "debian/changelog_backports" && \
    cp -ap "$backports_dir/changelog" "debian/changelog" && \
    bpo_version=`dpkg-parsechangelog -c1 | grep ^Version |cut -d' ' -f2 | grep bpo`

    dpkg-buildpackage -S -us -uc &&
    cp -ap "debian/changelog_backports" "debian/changelog"

    echo "Now here's a backports patch in $backports_dir/$distribution and its source"
    echo "package as ../"$package_name"_"$bpo_version".dsc."
    echo ""

    if [ $2 !="--noch-up" ]; then
      echo "Then, update stable chroot environment..."
      $sudo $buildtool --update $chroot_setting
    fi
  ;;

  *)
    echo "please specify option as 'init' or 'update'."
  ;;

esac

exit 0
