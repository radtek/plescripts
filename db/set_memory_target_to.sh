#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/dblib.sh
. ~/plescripts/gilib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r PARAMS="$*"
typeset -r str_usage=\
"Usage : $ME
	[-val=value|max]	ex 1024M or 1G. value can be negative.
	[-apply]
"

typeset 	val=undef
typeset		apply=no

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			shift
			;;

		-val=*)
			val=${1##*=}
			shift
			;;

		-apply)
			apply=yes
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

#ple_enable_log -params $PARAMS

if [ $apply == yes ]
then
	exit_if_param_undef val	"$str_usage"
fi

exit_if_ORACLE_SID_not_defined

# $1 value
function abs
{
	typeset v="$1"
	[ ${v:0:1} == - ] && echo ${v:1} || echo $v
}

# $1 %
# $2 valeur
# Valeur partielle = Pourcentage x Valeur totale / 100
function pct
{
	compute -i "$2 - ($1 * $2 / 100)"
}

# print to stdout yes if $1 negatif, else no
function negatif
{
	typeset v=$1
	[ "${v:0:1}" == "-" ] && echo yes || echo no
}

# Init variables : cur_memory_target, os_free_memory, shm_total, shm_available
function load_memory_info
{
	cur_memory_target=$(to_bytes $(orcl_parameter_value memory_max_target))
	os_free_memory=$(free -b|grep -E "^Mem:"|awk '{ print $4 }')

	read f1 shm_total shm_used shm_available rem<<<$(df -m /dev/shm|grep "shm$")

	shm_total=$(to_bytes ${shm_total}M)
	shm_available=$(to_bytes ${shm_available}M)
}

# Initialise asm_memory_target de l'instance ASM
function read_asm_memory_target
{
	typeset OSID=$ORACLE_SID
	typeset ASM_SID=$(ps -ef|grep [p]mon_+ASM|cut -d_ -f3)
	load_oraenv_for $ASM_SID
	asm_memory_target=$(orcl_parameter_value memory_max_target)
	asm_memory_target=$(to_bytes $asm_memory_target)
	load_oraenv_for $OSID
}

# Toutes les valeurs sont en bytes.

load_memory_info

typeset -i	max_memory_target=$(pct 5 $shm_total)

if command_exists crsctl
then
	read_asm_memory_target
	max_memory_target=$(( max_memory_target - asm_memory_target ))
fi

typeset set_max=no
if [ "$val" == max ]
then
	typeset -i val=$max_memory_target
	set_max=yes
elif [ "$val" == undef ]
then
	typeset -i val=-1
else
	typeset is_neg=$(negatif $val)

	typeset -i val=$(to_bytes $(abs $val))
	if [ $is_neg == yes ]
	then
		val=$(( cur_memory_target - val ))
	fi
fi

info	"OS free memory    : $(fmt_bytes_2_better $os_free_memory)"
info	"shm total         : $(fmt_bytes_2_better $shm_total)"
info	"shm available     : $(fmt_bytes_2_better $shm_available)"
if [ x"$asm_memory_target" != x ]
then
	info	"asm_memory_target : $(fmt_bytes_2_better $asm_memory_target)"
fi
info -n	"memory_max_target : $(fmt_bytes_2_better $cur_memory_target)"
info -f	", maximum : $(fmt_bytes_2_better $max_memory_target) ($(fmt_number $(to_mb ${max_memory_target}b))Mb)"
LN

if [ $val -eq -1 ]
then
	exit 0
fi

info -n "set memory_max_target to $(fmt_bytes_2_better $val) : "
typeset -ri	diff=$(( val - cur_memory_target ))
if [ $diff -gt 0 ]
then
	info -f "increase of $(fmt_bytes_2_better $diff)"
	if [ $val -gt $max_memory_target ]
	then
		LN
		error "/dev/shm is too low."
		LN
		exit 1
	fi
else
	info -f "decrease of $(fmt_bytes_2_better $(abs $diff))"
fi
LN

if [[ $set_max == yes && $val -lt $cur_memory_target ]]
then
	error "memory_max_target $(fmt_bytes_2_better $val) < current memory_target $(fmt_bytes_2_better $cur_memory_target)"
	LN
	exit 1
fi

if [[ $diff -gt 0 && $diff -gt $shm_available ]]
then
	LN
	error "No enough memory"
	LN
	exit 1
fi

if [ $apply == no ]
then
	info "add flag -apply to apply configuration."
	LN
	exit 0
fi

typeset -r backup_pfile='/tmp/p.txt'

# $1 size
function sql_set_memory_max_target
{
	set_sql_cmd "create pfile='$backup_pfile' from spfile;"
	set_sql_cmd "alter system set memory_max_target=$1 scope=spfile sid='*';"
}

line_separator
sqlplus_cmd "$(sql_set_memory_max_target $val)"
exec_cmd "~/plescripts/db/bounce_db.sh"
LN

line_separator
load_memory_info
info "OS free memory    : $(fmt_bytes_2_better $os_free_memory)"
info "shm total         : $(fmt_bytes_2_better $shm_total)"
info "shm available     : $(fmt_bytes_2_better $shm_available)"
info "memory_max_target : $(fmt_bytes_2_better $cur_memory_target)"
LN
