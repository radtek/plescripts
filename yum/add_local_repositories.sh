#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r str_usage=\
"Usage : $ME -role=master|infra" 

script_banner $ME $*

typeset role=undef

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			first_args=-emul
			shift
			;;

		-role=*)
			role=${1##*=}
			shift
			;;

		-h|-help|help)
			info "$str_usage"
			LN
			exit 1
			;;

		*)
			error "Arg '$1' invalid."
			LN
			info "$str_usage"
			exit 1
			;;
	esac
done

exit_if_param_invalid role "master infra" "$str_usage"

if [ $role == master ]
then
	url_is="baseurl=file:///mnt$infra_olinux_repository_path"
else
	url_is="baseurl=file://$infra_olinux_repository_path"
fi

if ! grep -q ol7_local /etc/yum.repos.d/public-yum-ol7.repo
then
	info "Add repo local_ol7_latest & local_ol7_UEKR4"
	cat <<-EOS >>/etc/yum.repos.d/public-yum-ol7.repo

	[local_ol7_latest]
	name=Oracle Linux \$releasever Latest (\$basearch)
	$url_is
	gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
	gpgcheck=1
	enabled=0

	[local_ol7_UEKR3]
	name=Latest Unbreakable Enterprise Kernel Release 3 for Oracle Linux \$releasever (\$basearch)
	$url_is
	gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
	gpgcheck=1
	enabled=0

	[local_ol7_UEKR4]
	name=Latest Unbreakable Enterprise Kernel Release 4 for Oracle Linux \$releasever (\$basearch)
	$url_is
	gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
	gpgcheck=1
	enabled=0
	EOS
else
	info "Repository ol7_local already configured."
fi
LN