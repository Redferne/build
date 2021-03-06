#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
#
# This is the image customization script

# NOTE: It is copied to /tmp directory inside the image
# and executed there inside chroot environment
# so don't reference any files that are not already installed

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

Main() {

	if [[ $BOARD == hummingboardpulse-imx8q ]] || [[ $BOARD == cubox-i ]]; then
		InstallIperf3
		InstallLibMBIM
		InstallLibQMI
		InstallModemManager
		InstallSpeedtest
	fi

	case $RELEASE in
		xenial)
			# your code here
			;;
		stretch)
			# your code here
			# InstallOpenMediaVault # uncomment to get an OMV 4 image
			;;
		buster)
			# your code here
			;;
		bionic)
			# your code here
			;;
	esac
} # Main

InstallOpenMediaVault() {
	# use this routine to create a Debian based fully functional OpenMediaVault
	# image (OMV 3 on Jessie, OMV 4 with Stretch). Use of mainline kernel highly
	# recommended!
	#
	# Please note that this variant changes Armbian default security 
	# policies since you end up with root password 'openmediavault' which
	# you have to change yourself later. SSH login as root has to be enabled
	# through OMV web UI first
	#
	# This routine is based on idea/code courtesy Benny Stark. For fixes,
	# discussion and feature requests please refer to
	# https://forum.armbian.com/index.php?/topic/2644-openmediavault-3x-customize-imagesh/

	echo root:openmediavault | chpasswd
	rm /root/.not_logged_in_yet
	. /etc/default/cpufrequtils
	export LANG=C LC_ALL="en_US.UTF-8"
	export DEBIAN_FRONTEND=noninteractive
	export APT_LISTCHANGES_FRONTEND=none

	case ${RELEASE} in
		jessie)
			OMV_Name="erasmus"
			OMV_EXTRAS_URL="https://github.com/OpenMediaVault-Plugin-Developers/packages/raw/master/openmediavault-omvextrasorg_latest_all3.deb"
			;;
		stretch)
			OMV_Name="arrakis"
			OMV_EXTRAS_URL="https://github.com/OpenMediaVault-Plugin-Developers/packages/raw/master/openmediavault-omvextrasorg_latest_all4.deb"
			;;
	esac

	# Add OMV source.list and Update System
	cat > /etc/apt/sources.list.d/openmediavault.list <<- EOF
	deb https://openmediavault.github.io/packages/ ${OMV_Name} main
	## Uncomment the following line to add software from the proposed repository.
	deb https://openmediavault.github.io/packages/ ${OMV_Name}-proposed main
	
	## This software is not part of OpenMediaVault, but is offered by third-party
	## developers as a service to OpenMediaVault users.
	# deb https://openmediavault.github.io/packages/ ${OMV_Name} partner
	EOF

	# Add OMV and OMV Plugin developer keys, add Cloudshell 2 repo for XU4
	if [ "${BOARD}" = "odroidxu4" ]; then
		add-apt-repository -y ppa:kyle1117/ppa
		sed -i 's/jessie/xenial/' /etc/apt/sources.list.d/kyle1117-ppa-jessie.list
	fi
	mount --bind /dev/null /proc/mdstat
	apt-get update
	apt-get --yes --force-yes --allow-unauthenticated install openmediavault-keyring
	apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 7AA630A1EDEE7D73
	apt-get update

	# install debconf-utils, postfix and OMV
	HOSTNAME="${BOARD}"
	debconf-set-selections <<< "postfix postfix/mailname string ${HOSTNAME}"
	debconf-set-selections <<< "postfix postfix/main_mailer_type string 'No configuration'"
	apt-get --yes --force-yes --allow-unauthenticated  --fix-missing --no-install-recommends \
		-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install \
		debconf-utils postfix
	# move newaliases temporarely out of the way (see Ubuntu bug 1531299)
	cp -p /usr/bin/newaliases /usr/bin/newaliases.bak && ln -sf /bin/true /usr/bin/newaliases
	sed -i -e "s/^::1         localhost.*/::1         ${HOSTNAME} localhost ip6-localhost ip6-loopback/" \
		-e "s/^127.0.0.1   localhost.*/127.0.0.1   ${HOSTNAME} localhost/" /etc/hosts
	sed -i -e "s/^mydestination =.*/mydestination = ${HOSTNAME}, localhost.localdomain, localhost/" \
		-e "s/^myhostname =.*/myhostname = ${HOSTNAME}/" /etc/postfix/main.cf
	apt-get --yes --force-yes --allow-unauthenticated  --fix-missing --no-install-recommends \
		-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install \
		openmediavault

	# install OMV extras, enable folder2ram and tweak some settings
	FILE=$(mktemp)
	wget "$OMV_EXTRAS_URL" -qO $FILE && dpkg -i $FILE
	
	/usr/sbin/omv-update
	# Install flashmemory plugin and netatalk by default, use nice logo for the latter,
	# tweak some OMV settings
	. /usr/share/openmediavault/scripts/helper-functions
	apt-get -y -q install openmediavault-netatalk openmediavault-flashmemory
	AFP_Options="mimic model = Macmini"
	SMB_Options="min receivefile size = 16384\nwrite cache size = 524288\ngetwd cache = yes\nsocket options = TCP_NODELAY IPTOS_LOWDELAY"
	xmlstarlet ed -L -u "/config/services/afp/extraoptions" -v "$(echo -e "${AFP_Options}")" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/smb/extraoptions" -v "$(echo -e "${SMB_Options}")" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/flashmemory/enable" -v "1" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/ssh/enable" -v "1" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/ssh/permitrootlogin" -v "0" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/time/ntp/enable" -v "1" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/time/timezone" -v "UTC" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/network/dns/hostname" -v "${HOSTNAME}" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/monitoring/perfstats/enable" -v "0" /etc/openmediavault/config.xml
	echo -e "OMV_CPUFREQUTILS_GOVERNOR=${GOVERNOR}" >>/etc/default/openmediavault
	echo -e "OMV_CPUFREQUTILS_MINSPEED=${MIN_SPEED}" >>/etc/default/openmediavault
	echo -e "OMV_CPUFREQUTILS_MAXSPEED=${MAX_SPEED}" >>/etc/default/openmediavault
	for i in netatalk samba flashmemory ssh ntp timezone interfaces cpufrequtils monit collectd rrdcached ; do
		/usr/sbin/omv-mkconf $i
	done
	/sbin/folder2ram -enablesystemd || true
	sed -i 's|-j /var/lib/rrdcached/journal/ ||' /etc/init.d/rrdcached

	# Fix multiple sources entry on ARM with OMV4
	sed -i '/stretch-backports/d' /etc/apt/sources.list

	# rootfs resize to 7.3G max and adding omv-initsystem to firstrun -- q&d but shouldn't matter
	echo 15500000s >/root/.rootfs_resize
	sed -i '/systemctl\ disable\ armbian-firstrun/i \
	mv /usr/bin/newaliases.bak /usr/bin/newaliases \
	export DEBIAN_FRONTEND=noninteractive \
	sleep 3 \
	apt-get install -f -qq python-pip python-setuptools || exit 0 \
	pip install -U tzupdate \
	tzupdate \
	read TZ </etc/timezone \
	/usr/sbin/omv-initsystem \
	xmlstarlet ed -L -u "/config/system/time/timezone" -v "${TZ}" /etc/openmediavault/config.xml \
	/usr/sbin/omv-mkconf timezone \
	lsusb | egrep -q "0b95:1790|0b95:178a|0df6:0072" || sed -i "/ax88179_178a/d" /etc/modules' /usr/lib/armbian/armbian-firstrun
	sed -i '/systemctl\ disable\ armbian-firstrun/a \
	sleep 30 && sync && reboot' /usr/lib/armbian/armbian-firstrun

	# add USB3 Gigabit Ethernet support
	echo -e "r8152\nax88179_178a" >>/etc/modules

	# Special treatment for ODROID-XU4 (and later Amlogic S912, RK3399 and other big.LITTLE
	# based devices). Move all NAS daemons to the big cores. With ODROID-XU4 a lot
	# more tweaks are needed. CS2 repo added, CS1 workaround added, coherent_pool=1M
	# set: https://forum.odroid.com/viewtopic.php?f=146&t=26016&start=200#p197729
	# (latter not necessary any more since we fixed it upstream in Armbian)
	case ${BOARD} in
		odroidxu4)
			HMP_Fix='; taskset -c -p 4-7 $i '
			# Cloudshell stuff (fan, lcd, missing serials on 1st CS2 batch)
			echo "H4sIAKdXHVkCA7WQXWuDMBiFr+eveOe6FcbSrEIH3WihWx0rtVbUFQqCqAkYGhJn
			tF1x/vep+7oebDfh5DmHwJOzUxwzgeNIpRp9zWRegDPznya4VDlWTXXbpS58XJtD
			i7ICmFBFxDmgI6AXSLgsiUop54gnBC40rkoVA9rDG0SHHaBHPQx16GN3Zs/XqxBD
			leVMFNAz6n6zSWlEAIlhEw8p4xTyFtwBkdoJTVIJ+sz3Xa9iZEMFkXk9mQT6cGSQ
			QL+Cr8rJJSmTouuuRzfDtluarm1aLVHksgWmvanm5sbfOmY3JEztWu5tV9bCXn4S
			HB8RIzjoUbGvFvPw/tmr0UMr6bWSBupVrulY2xp9T1bruWnVga7DdAqYFgkuCd3j
			vORUDQgej9HPJxmDDv+3WxblBSuYFH8oiNpHz8XvPIkU9B3JVCJ/awIAAA==" \
			| tr -d '[:blank:]' | base64 --decode | gunzip -c >/usr/local/sbin/cloudshell2-support.sh
			chmod 755 /usr/local/sbin/cloudshell2-support.sh
			apt install -y i2c-tools odroid-cloudshell cloudshell2-fan
			sed -i '/systemctl\ disable\ armbian-firstrun/i \
			lsusb | grep -q -i "05e3:0735" && sed -i "/exit\ 0/i echo 20 > /sys/class/block/sda/queue/max_sectors_kb" /etc/rc.local \
			/usr/sbin/i2cdetect -y 1 | grep -q "60: 60" && /usr/local/sbin/cloudshell2-support.sh' /usr/lib/armbian/armbian-firstrun
			;;
		bananapim3|nanopifire3|nanopct3plus|nanopim3)
			HMP_Fix='; taskset -c -p 4-7 $i '
			;;
		edge*|ficus|firefly-rk3399|nanopct4|nanopim4|nanopineo4|renegade-elite|roc-rk3399-pc|rockpro64)
			HMP_Fix='; taskset -c -p 4-5 $i '
			;;
	esac
	echo "* * * * * root for i in \`pgrep \"ftpd|nfsiod|smbd|afpd|cnid\"\` ; do ionice -c1 -p \$i ${HMP_Fix}; done >/dev/null 2>&1" \
		>/etc/cron.d/make_nas_processes_faster
	chmod 600 /etc/cron.d/make_nas_processes_faster

	# add SATA port multiplier hint if appropriate
	[ "${LINUXFAMILY}" = "sunxi" ] && \
		echo -e "#\n# If you want to use a SATA PM add \"ahci_sunxi.enable_pmp=1\" to bootargs above" \
		>>/boot/boot.cmd

	# Filter out some log messages
	echo ':msg, contains, "do ionice -c1" ~' >/etc/rsyslog.d/omv-armbian.conf
	echo ':msg, contains, "action " ~' >>/etc/rsyslog.d/omv-armbian.conf
	echo ':msg, contains, "netsnmp_assert" ~' >>/etc/rsyslog.d/omv-armbian.conf
	echo ':msg, contains, "Failed to initiate sched scan" ~' >>/etc/rsyslog.d/omv-armbian.conf

	# Fix little python bug upstream Debian 9 obviously ignores
	if [ -f /usr/lib/python3.5/weakref.py ]; then
		wget -O /usr/lib/python3.5/weakref.py \
		https://raw.githubusercontent.com/python/cpython/9cd7e17640a49635d1c1f8c2989578a8fc2c1de6/Lib/weakref.py
	fi

	# clean up and force password change on first boot
	umount /proc/mdstat
	chage -d 0 root
} # InstallOpenMediaVault

UnattendedStorageBenchmark() {
	# Function to create Armbian images ready for unattended storage performance testing.
	# Useful to use the same OS image with a bunch of different SD cards or eMMC modules
	# to test for performance differences without wasting too much time.

	rm /root/.not_logged_in_yet

	apt-get -qq install time

	wget -qO /usr/local/bin/sd-card-bench.sh https://raw.githubusercontent.com/ThomasKaiser/sbc-bench/master/sd-card-bench.sh
	chmod 755 /usr/local/bin/sd-card-bench.sh

	sed -i '/^exit\ 0$/i \
	/usr/local/bin/sd-card-bench.sh &' /etc/rc.local
} # UnattendedStorageBenchmark

InstallAdvancedDesktop()
{
	apt install -yy transmission libreoffice libreoffice-style-tango meld remmina thunderbird kazam avahi-daemon
	[[ -f /usr/share/doc/avahi-daemon/examples/sftp-ssh.service ]] && cp /usr/share/doc/avahi-daemon/examples/sftp-ssh.service /etc/avahi/services/
	[[ -f /usr/share/doc/avahi-daemon/examples/ssh.service ]] && cp /usr/share/doc/avahi-daemon/examples/ssh.service /etc/avahi/services/
	apt clean
} # InstallAdvancedDesktop

InstallLibQMI()
{
	cd /tmp
	apt update
	apt install -y checkinstall bash-completion build-essential git ne picocom autoconf automake autoconf-archive libtool libglib2.0-dev libgudev-1.0-dev gettext
	export LIB_DIR=$(pkg-config --variable=libdir gudev-1.0)
	echo "Installing libqmi to LIBDIR: [${LIB_DIR}]"
	apt remove -y --purge libqmi-*
	wget -t 0 -q https://gitlab.freedesktop.org/mobile-broadband/libqmi/-/archive/master/libqmi-master.tar.gz
	tar xf libqmi-master.tar.gz
	cd libqmi-master
	./autogen.sh --prefix=/usr --enable-mbim-qmux --disable-maintainer-mode --libdir=${LIB_DIR} --libexecdir=${LIB_DIR}
	VERSION=$(awk '/PACKAGE_VERSION =/{print $NF}' Makefile)
	echo "Compiling libqmi-${VERSION}"
	make --jobs

	echo "Installing libqmi-proxy..."
	cd src/qmi-proxy
	checkinstall -y -D --maintainer=nobody@nowhere.com --install=yes --pkgname libqmi-proxy --pkgversion=${VERSION} --nodoc \
    --exclude=/usr/include,/usr/lib/pkgconfig
    if [ "$?" -ne "0" ]; then
    	echo "checkinstall libqmi-proxy failed!"
    	exit 1
    fi
    mv libqmi*.deb /var/cache/apt/archives/
	cd ../..


	echo "Installing libqmi-utils..."
	cat <<-EOF > inst.sh
	#!/bin/bash
	make -C utils install
	make -C src/qmicli install
	make -C src/qmi-firmware-update install
	EOF
	chmod a+x inst.sh
	checkinstall -y -D --maintainer=nobody@nowhere.com --install=yes --pkgname libqmi-utils --pkgversion=${VERSION} --nodoc ./inst.sh
    if [ "$?" -ne "0" ]; then
    	echo "checkinstall libqmi-utils failed!"
    	exit 1
    fi
    mv libqmi*.deb /var/cache/apt/archives/

	echo "Installing libqmi-glib-dev..."
	cat <<-EOF > inst.sh
	#!/bin/bash
	make -C data install
	make -C src/libqmi-glib install-data
	EOF
	chmod a+x inst.sh
	checkinstall -y -D --maintainer=nobody@nowhere.com --install=yes --pkgname libqmi-glib-dev --pkgversion=${VERSION} --nodoc ./inst.sh
    if [ "$?" -ne "0" ]; then
    	echo "checkinstall libqmi-glib-dev failed!"
    	exit 1
    fi
    mv libqmi*.deb /var/cache/apt/archives/

	echo "Installing libqmi-glib5..."
	cd src/libqmi-glib
    checkinstall -y -D --maintainer=nobody@nowhere.com --install=yes --pkgname libqmi-glib5 --pkgversion=${VERSION} --nodoc \
    --exclude=/usr/include,/usr/lib/pkgconfig
    if [ "$?" -ne "0" ]; then
    	echo "checkinstall libqmi-glib5 failed!"
    	exit 1
    fi
    mkdir -p /var/cache/apt/archives/
	echo "Copy .deb to /var/cache/apt/archives/"
    mv libqmi*.deb /var/cache/apt/archives/
	cd ../..

	ldconfig
	cd ..
	rm -rf libqmi-master.tar.gz libqmi-master
	cd ..
}

InstallLibMBIM()
{
	cd /tmp
	apt update
	apt install -y bash-completion build-essential git ne picocom autoconf automake autoconf-archive libtool libglib2.0-dev libgudev-1.0-dev gettext
	export LIB_DIR=$(pkg-config --variable=libdir gudev-1.0)
	echo "Installing libmbim to LIBDIR: [${LIB_DIR}]"
	apt remove -y --purge libmbim-*
	wget -t 0 -q https://gitlab.freedesktop.org/mobile-broadband/libmbim/-/archive/master/libmbim-master.tar.gz
	tar xf libmbim-master.tar.gz
	cd libmbim-master
	./autogen.sh --prefix=/usr --disable-maintainer-mode --libdir=${LIB_DIR} --libexecdir=${LIB_DIR}
	VERSION=$(awk '/PACKAGE_VERSION =/{print $NF}' Makefile)
	echo "Compiling libmbim-${VERSION}"
	make --jobs


	echo "Installing libmbim-proxy..."
	cd src/mbim-proxy
    checkinstall -y -D --maintainer=nobody@nowhere.com --install=yes --pkgname libmbim-proxy --pkgversion=${VERSION} --nodoc 
    if [ "$?" -ne "0" ]; then
    	echo "checkinstall libmbim-proxy failed!"
    	exit 1
    fi
    mkdir -p /var/cache/apt/archives/
	echo "Copy .deb to /var/cache/apt/archives/"
    mv libmbim*.deb /var/cache/apt/archives/
    cd ../..

	echo "Installing libmbim-utils..."
	cat <<-EOF > inst.sh
	#!/bin/bash
	make -C utils install
	make -C src/mbimcli install
	EOF
	chmod a+x inst.sh
    checkinstall -y -D --maintainer=nobody@nowhere.com --install=yes --pkgname libmbim-utils --pkgversion=${VERSION} --nodoc ./inst.sh
    if [ "$?" -ne "0" ]; then
    	echo "checkinstall libmbim-proxy failed!"
    	exit 1
    fi
    mkdir -p /var/cache/apt/archives/
	echo "Copy .deb to /var/cache/apt/archives/"
    mv libmbim*.deb /var/cache/apt/archives/

	echo "Installing libmbim-glib-dev..."
	cat <<-EOF > inst.sh
	#!/bin/bash
	make -C data install
	make -C src/libmbim-glib install-data
	EOF
	chmod a+x inst.sh
	checkinstall -y -D --maintainer=nobody@nowhere.com --install=yes --pkgname libmbim-glib-dev --pkgversion=${VERSION} --nodoc ./inst.sh
    if [ "$?" -ne "0" ]; then
    	echo "checkinstall libmbim-glib-dev failed!"
    	exit 1
    fi
    mv libmbim*.deb /var/cache/apt/archives/

	echo "Installing libmbim-glib4..."
	cd src/libmbim-glib
    checkinstall -y -D --maintainer=nobody@nowhere.com --install=yes --pkgname libmbim-glib4 --pkgversion=${VERSION} --nodoc \
    --exclude=/usr/include,/usr/lib/pkgconfig
    if [ "$?" -ne "0" ]; then
    	echo "checkinstall libmbim-glib4 failed!"
    	exit 1
    fi
    mkdir -p /var/cache/apt/archives/
	echo "Copy .deb to /var/cache/apt/archives/"
    mv libmbim*.deb /var/cache/apt/archives/
    cd ../..


	ldconfig
	cd ..
	rm -rf libmbim-master.tar.gz libmbim-master
	cd ..
}

InstallModemManager()
{
	cd /tmp
	apt update
	apt install -y bash-completion build-essential git ne picocom autoconf autopoint automake autoconf-archive libtool libglib2.0-dev libgudev-1.0-dev gettext libsystemd-dev xsltproc
	export LIB_DIR=$(pkg-config --variable=libdir gudev-1.0)
	echo "Installing modemmanager to LIBDIR: [${LIB_DIR}]"
	apt remove -y --purge modemmanager
	wget -t 0 -q https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/archive/master/ModemManager-master.tar.gz
	tar xf ModemManager-master.tar.gz
	cd ModemManager-master
	./autogen.sh --prefix=/usr --disable-maintainer-mode --libdir=${LIB_DIR} --libexecdir=${LIB_DIR} --with-systemd-journal=yes --with-systemd-suspend-resume=no --with-at-command-via-dbus --with-udev-base-dir=/lib/udev --with-systemdsystemunitdir=/lib/systemd/system --with-dbus-sys-dir=/etc/dbus-1/system.d
	VERSION=$(awk '/PACKAGE_VERSION =/{print $NF}' Makefile)
	echo "Compiling modemmanager-${VERSION}"
    make clean
	make --jobs

	echo "Installing libmm-glib0..."
	cd libmm-glib
	checkinstall -y -D --maintainer=nobody@nowhere.com --fstrans=yes --install=yes --pkgname libmm-glib0 --pkgversion=${VERSION} --nodoc \
    --exclude=/usr/include,/usr/lib/pkgconfig \
	make install-exec
    if [ "$?" -ne "0" ]; then
    	echo "checkinstall libmm-glib0 failed!"
    	exit 1
    fi
	echo "Copy .deb to /var/cache/apt/archives/"
    mv libmm-glib0*.deb /var/cache/apt/archives/
    cd ..

	echo "Installing modemmanager..."
	mkdir -p /usr/share/icons/hicolor/22x22/apps
    checkinstall -y -D --maintainer=nobody@nowhere.com --fstrans=yes --install=yes --pkgname modemmanager --pkgversion=${VERSION} --nodoc \
    --exclude=${LIB_DIR}/libmm-glib*,/usr/include,/usr/lib/pkgconfig

    if [ "$?" -ne "0" ]; then
    	echo "checkinstall modemmanager failed!"
    	exit 1
    fi
    mkdir -p /var/cache/apt/archives/
	echo "Copy .deb to /var/cache/apt/archives/"
    mv modemmanager*.deb /var/cache/apt/archives/
#	make install
	ldconfig
	systemctl enable ModemManager.service
	cd ..
	rm -rf ModemManager-master.tar.gz ModemManager-master
}


InstallSpeedtest()
{
	cd /tmp
	apt install -y gnupg1 apt-transport-https dirmngr
	export INSTALL_KEY=379CE192D401AB61
	export DEB_DISTRO=$(lsb_release -sc)
	apt-key adv --keyserver keyserver.ubuntu.com --recv-keys $INSTALL_KEY
	echo "deb https://ookla.bintray.com/debian ${DEB_DISTRO} main" | tee /etc/apt/sources.list.d/speedtest.list
	apt update
	apt remove speedtest-cli
	apt install -y speedtest ethtool telnet tftp tftpd traceroute ftp
	cd ..
}

InstallIperf3()
{
	cd /tmp
	apt update
	apt install -y checkinstall avahi-daemon libnss-mdns bash-completion build-essential git ne picocom autoconf automake autoconf-archive libtool libglib2.0-dev libgudev-1.0-dev gettext
	export LIB_DIR=$(pkg-config --variable=libdir gudev-1.0)
	echo "Installing iperf3 to LIBDIR: [${LIB_DIR}]"
	apt update
	apt install -y unzip
	apt remove -y --purge iperf iperf3 libiperf0
	wget -t 0 -q https://github.com/esnet/iperf/archive/master.zip
	unzip -qo master.zip
	cd iperf-master
	./configure --prefix=/usr --libdir=${LIB_DIR} --libexecdir=${LIB_DIR}
	VERSION=$(awk '/PACKAGE_VERSION =/{print $NF}' Makefile)
        VERSION=$(echo $VERSION | sed 's/[^0-9.]*//g')
	echo "Compiling iperf3-${VERSION}"
	make --jobs

	echo "Installing libiperf0..."
	checkinstall -y -D --maintainer=nobody@nowhere.com --fstrans=yes --install=yes --pkgname libiperf0 --pkgversion=${VERSION} --nodoc \
    --exclude=/usr/include,/usr/lib/pkgconfig,/usr/bin,/usr/share \

    if [ "$?" -ne "0" ]; then
    	echo "checkinstall libiperf0 failed!"
    	exit 1
    fi
	echo "Copy .deb to /var/cache/apt/archives/"
    mv libiperf0*.deb /var/cache/apt/archives/

	echo "Installing iperf3..."
    checkinstall -y -D --maintainer=nobody@nowhere.com --install=yes --pkgname iperf3 --pkgversion=${VERSION} --nodoc \
    --exclude=/usr/include,/usr/lib/pkgconfig,/usr/lib,${LIB_DIR} \

    if [ "$?" -ne "0" ]; then
    	echo "checkinstall iperf3 failed!"
    	exit 1
    fi
    mkdir -p /var/cache/apt/archives/
	echo "Copy .deb to /var/cache/apt/archives/"
    mv iperf3*.deb /var/cache/apt/archives/
#	make install
	ldconfig
	cd ..
	rm -rf master.zip iperf-master
	cd ..
}


Main "$@"
