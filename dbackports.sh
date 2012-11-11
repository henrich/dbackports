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
# issue: can I remove root priv for cowbuilder/pbuilder via fakeroot?
# issue: sometimes cowbuilder environment is broken. Can I care about it?
# issue: automatic debhelper compatible version change
# 

set -e

usage()
{
        echo  "Usage: dbackports [init|update|build|discard]"
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

# get original version if $backports_dir/changelog exists
if [ -f $backports_dir/changelog ]; then
	package_name=`dpkg-parsechangelog -c1 -l$backports_dir/changelog |grep ^Source |cut -d' ' -f2`
	epoch_package_version=`dpkg-parsechangelog -c1 -l$backports_dir/changelog |grep ^Version |cut -d' ' -f2`
        package_version="${epoch_package_version#*:}"
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
        mkdir $backports_dir && cp debian/changelog $backports_dir && \
            dch --bpo -m "For detail of changes, see $backports_dir/$distribution"
        if [ -d .pc ]; then
            rm -rf .pc
        fi
          quilt new $distribution > /dev/null && \
          for file in `find debian $common_exclude` 
          do
	    echo $file >> "$backports_dir"/target_list
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
        if [ -z `grep $update_file $backports_dir/target_list` ]; then
             quilt add -P "$distribution" $update_file
        fi
    done
    quilt refresh 2>&1 >/dev/null 

    (echo "$package_version" | grep "bpo" &&  \
      dch -i -m "update backports.") || \
      dch -e -D "$distribution"-backports \
        -m "For detail of changes, see debian/backports/$distribution"

    dpkg-buildpackage -S -us -uc > /dev/null

    echo " "
    echo "Now here's a backports patch in $backports_dir/$distribution and its source."
    echo "Ready to builds."
    echo " "
  ;;

  discard)
    if [ ! -z $2 ]; then
	rm -rf debian && tar xf $2
    elif [ -f ../"$package_name"_"$package_version".debian.tar.* ]; then
	rm -rf debian && tar xf ../"$package_name"-"$package_version".debian.tar.*
    else
	    echo "Please specify debian.tar.[gz|bz2|xz] file, \
		    cannot rollback to before modifying source."
    fi
  ;;

  build)
    epoch_bpo_version=`dpkg-parsechangelog -c1 | grep ^Version |cut -d' ' -f2 | grep bpo`
    bpo_version="${epoch_bpo_version#*:}"

    $sudo $buildtool --build ../"$package_name"_"$bpo_version".dsc $chroot_setting
  ;;

  *)
    echo "please specify option."
    usage
  ;;

esac

exit 0
