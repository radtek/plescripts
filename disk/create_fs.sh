#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/disklib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0

typeset -r str_usage=\
"Usage : $ME
	-mount_point=name
	[-device=check]     or full device name : /dev/sdb,/dev/sdc ...
	[-disks=1]          number of disks, only if -device=check
	-suffix_vglv=name   => vg\$suffix, lv\$suffix
	-type_fs=name
	[-netdev]           add _netdev to mount point options
"

script_banner $ME $*

typeset		mount_point=undef
typeset	-a	device_list=( "check" )
typeset		disks=1
typeset		suffix_vglv=undef
typeset		type_fs=undef
typeset		netdev=no

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			first_args=-emul
			shift
			;;

		-mount_point=*)
			mount_point=${1##*=}
			shift
			;;

		-device=*)
			disks=0
			while IFS=',' read dev
			do
				device_list+=( $dev )
				((++disks))
			done<<<"${1##*=}"
			shift
			;;

		-disks=*)
			disks=${1##*=}
			shift
			;;

		-suffix_vglv=*)
			suffix_vglv=${1##*=}
			shift
			;;

		-type_fs=*)
			type_fs=${1##*=}
			shift
			;;

		-netdev)
			netdev=yes
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

exit_if_param_undef mount_point	"$str_usage"
exit_if_param_undef suffix_vglv	"$str_usage"
exit_if_param_undef type_fs		"$str_usage"

typeset	-r	vg_name=vg${suffix_vglv}
typeset	-r	lv_name=lv${suffix_vglv}

if [ "${device_list[0]}" == check ]
then
	info "Search $disks disks unused :"

	device_list=()

	typeset -i idisk=0
	while read device
	do
		[ x"$device" == x ] && break || true

		device_list+=( $device )
		((++idisk))
		[ $idisk -eq $disks ] && break || true
	done<<<"$(get_unused_disks_without_partitions)"

	info "Device found $idisk : ${device_list[*]}"
	LN
	if [ $idisk -ne $disks ]
	then
		error "Not enougth disks."
		LN
		exit 1
	fi
fi

info "Create fs $type_fs on devices ${device_list[*]} : mount point $mount_point"
LN

typeset -i idisk=0
for device in ${device_list[*]}
do
	((++idisk))

	add_partition_to $device
	sleep 1

	typeset	part_name=${device}1

	exec_cmd pvcreate $part_name
	sleep 1

	if [ $idisk -eq 1 ]
	then
		exec_cmd vgcreate $vg_name $part_name
	else
		exec_cmd vgextend $vg_name $part_name
	fi
	LN
done

sleep 1
exec_cmd lvcreate -y -l 100%FREE -n $lv_name $vg_name
exec_cmd mkfs -t $type_fs /dev/$vg_name/$lv_name
exec_cmd mkdir -p $mount_point
typeset mp_options=defaults
[ $netdev == yes ] && mp_options="_netdev,$mp_options" || true
exec_cmd "echo \"/dev/mapper/$vg_name-$lv_name $mount_point $type_fs $mp_options 0 0\" >> /etc/fstab"
exec_cmd mount $mount_point
