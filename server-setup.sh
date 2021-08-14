#!/bin/bash

#!/bin/bash

function check_perms {
	#  Save my sanity if people think...
        #  Forget that last line of comment.
        if [ $(/usr/bin/id -u) != "0" ]
	then
		die 'This script must be ran by using sudo or under the root user.'
	fi

	if [ ! -f /etc/debian_version ]
	then
		die "This distribution is not supported. Sorry."
	fi
}

function check_install {
	if [ -z "`which "$1" 2>/dev/null`" ]
	then
		executable=$1
		shift
		while [ -n "$1" ]
		do
			DEBIAN_FRONTEND=noninteractive apt-get -q -y install "$1"
			apt-get clean
			print_info "$1 is already installed for $executable"
			shift
		done
	else
		print_warn "$2 has already been installed."
	fi
}

function check_remove {
	if [ -n "`which "$1" 2>/dev/null`" ]
	then
		DEBIAN_FRONTEND=noninteractive apt-get -q -y remove --purge "$2"
		apt-get clean
		print_info "$2 has been removed."
	else
		print_warn "$2 is currently not installed."
	fi
}


function die {
	echo "ERROR: $1" > /dev/null 1>&2
	exit 1
}

function print_info {
	echo -n -e '\e[1;36m'
	echo -n $1
	echo -e '\e[0m'
}

function print_warn {
	echo -n -e '\e[1;33m'
	echo -n $1
	echo -e '\e[0m'
}

function apt_clean {
	apt-get -q -y autoclean
	apt-get -q -y clean
}

function update_upgrade {
	#  Run through the apt-get update/upgrade first.
	#  This should be done before we try to install any package
	apt-get -q -y update
	apt-get -q -y upgrade

	#  Just in case there's packages that we can remove to save
        #  some storage space for people.
	apt-get -q -y autoremove
}

##
#   Checks for *commonly required* applications
##

function install_nano {
	check_install nano nano
}

function install_htop {
	check_install htop htop
}

function install_git {
	check_install git git
}

function install_curl {
	check_install curl curl
}

function install_ufw {
	check_install ufw ufw
}

function install_exim4 {
	check_install mail exim4
	if [ -f /etc/exim4/update-exim4.conf.conf ]
	then
		sed -i \
			"s/dc_eximconfig_configtype='local'/dc_eximconfig_configtype='internet'/" \
			/etc/exim4/update-exim4.conf.conf
		invoke-rc.d exim4 restart
	fi
}

function install_dotdeb {
	# Debian 6
	if grep ^6. /etc/debian_version > /dev/null
	then
		echo "deb http://packages.dotdeb.org squeeze all" >> /etc/apt/sources.list
		echo "deb-src http://packages.dotdeb.org squeeze all" >> /etc/apt/sources.list
	fi

	# Debian 7
	if grep ^7. /etc/debian_version > /dev/null
	then
		echo "deb http://packages.dotdeb.org wheezy all" >> /etc/apt/sources.list
		echo "deb-src http://packages.dotdeb.org wheezy all" >> /etc/apt/sources.list
	fi

	wget -q -O - http://www.dotdeb.org/dotdeb.gpg | apt-key add -
}

function install_syslogd {
	#  Let's just use a simple vanilla syslogd. There is no need to log to
	#  so many files ever in my mind. Just dump them into a folder that 
        #  allows for some simple organization.
        #  
	#  E.g.  /var/log/( cron/mail/messages )
	check_install /usr/sbin/syslogd inetutils-syslogd
	invoke-rc.d inetutils-syslogd stop

	for file in /var/log/*.log /var/log/mail.* /var/log/debug /var/log/syslog
	do
		[ -f "$file" ] && rm -f "$file"
	done
	for dir in fsck news
	do
		[ -d "/var/log/$dir" ] && rm -rf "/var/log/$dir"
	done

	cat > /etc/syslog.conf <<END
        *.*;mail.none;cron.none -/var/log/messages
        cron.*				  -/var/log/cron
        mail.*				  -/var/log/mail
        END

	[ -d /etc/logrotate.d ] || mkdir -p /etc/logrotate.d
	cat > /etc/logrotate.d/inetutils-syslogd <<END
        /var/log/cron
        /var/log/mail
        /var/log/messages {
                rotate 4
                weekly
                missingok
                notifempty
                compress
                sharedscripts
                postrotate
        /etc/init.d/inetutils-syslogd reload >/dev/null
                endscript
        }
END

	invoke-rc.d inetutils-syslogd start
}

function remove_unneeded {
	#  Some Debian Distros still have portmap installed.
	check_remove /sbin/portmap portmap

	#  Remove rsyslogd, which allocates ~30MB privvmpages on an OpenVZ system,
	#  which could make some low-end VPS inoperatable at times.
	check_remove /usr/sbin/rsyslogd rsyslog

	# Other packages that are often installed, but usually not needed.
	check_remove /usr/sbin/apache2 'apache2*'
	check_remove /usr/sbin/named 'bind9*'
	check_remove /usr/sbin/smbd 'samba*'
	check_remove /usr/sbin/nscd nscd

	#  Need to stop sendmail.
        #  Removing it doesn't seem to work ever.
	if [ -f /usr/lib/sm.bin/smtpd ]
	then
		invoke-rc.d sendmail stop
		check_remove /usr/lib/sm.bin/smtpd 'sendmail*'
	fi
}

##
#  Here we go!
##
export PATH=/bin:/usr/bin:/sbin:/usr/sbin

check_sanity
case "$1" in
apt)
	update_apt_sources
	;;
nano)
	install_nano $2
	;;
htop)
	install_htop $2
	;;
git)
	install_git $2
	;;
curl)
	install_curl $2
	;;
ufw)
	install_ufw $2
	;;
exim4)
	install_exim4
	;;
dotdeb)
	install_dotdeb
	;;
syslogd)
	install_syslogd
	;;
system)
	remove_unneeded
	update_upgrade
	install_nano
	install_htop
	install_nano
	install_git
	install_curl
	install_ufw
	install_exim4
	install_dordeb
	install_syslogd
	apt_clean
	;;
*)
	show_os_arch_version
	echo '  '
	echo 'Usage:' `basename $0` '[option] [argument]'
	echo 'Available options (in recomended order):'
        echo '  '
	echo '  - dotdeb                 (install dotdeb apt source for nginx 1.2+)'
	echo '  - system                 (remove unneeded, upgrade system, install software)'
	echo '  - exim4                  (install exim4 mail server)'
	echo '  '
	;;
esac
