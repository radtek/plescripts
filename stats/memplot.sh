#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/cfglib.sh
. ~/plescripts/stats/statslib.sh
#. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r PARAMS="$*"

typeset node=-1
typeset	loop=yes
typeset date=undef
typeset time=undef
typeset server=""
typeset title=""
typeset show_log_only=no
typeset	clear_log=no
typeset	range_mn=5
typeset	skip_standby=no

typeset -r str_usage=\
"Usage : $ME
		[-node=<#>]
		[-range_mn=$range_mn]
		[-no_loop]
		[-title=<str>]
		[-date=<YYYY-MM-DD>] not set, search last date.
		[-time=<HHhMM>]      not set, search last time.
		[-server=<name>]     can be omitted with only one server.
		[-start_at=HHhMM]    skip tt before HHhMM
		[-show_log_only]     show log files.
		[-clear_log]         remove log files.
		[-skip_standby]

Display files produced by memstats.sh with gnuplot"

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			first_args=-emul
			shift
			;;

		-node=*)
			node=${1##*=}
			shift
			;;

		-range_mn=*)
			range_mn=${1##*=}
			shift
			;;

		-no_loop)
			loop=no
			shift
			;;

		-date=*)
			date=${1##*=}
			shift
			;;

		-time=*)
			time=${1##*=}
			shift
			;;

		-title=*)
			title=${1##*=}_
			shift
			;;

		-server=*)
			server=${1##*=}_
			shift
			;;

		-show_log_only)
			show_log_only=yes
			shift
			;;

		-clear_log)
			clear_log=yes
			shift
			;;

		-skip_standby)
			skip_standby=yes
			shift
			;;

		*)
			error "Arg '$1' invalid."
			LN
			info "$str_usage"
			exit 1
			;;
	esac
done

typeset		db=undef
typeset		launch_second_script=no

# HH:MM:SS
function time_to_secs
{
	typeset -r ti=$1

	IFS=':' read hour mn s<<<"$ti"
	compute "$hour*60*60 + $mn*60 + $s"
}

typeset log_shm=undef
typeset log_mem=undef
typeset log_swap=undef

function set_to_last_date
{
	last_log_path=$(ls -d ${PLELOG_ROOT}/* | tail -1)
	date=${last_log_path##*/}
	info "set date to $date"
	LN
}

function show_formatted_logs
{
	typeset log_mem=${PLESTATS_PATH}/*${server}${title}memstat.log
	for f in $log_mem
	do
		IFS='_' read log_time srvname title1 rem<<<"${f##*/}"
		typeset msg=$(printf "$ME -title=%s -server=%s -time=%s" ${title1} $srvname $log_time)
		info "$msg"
	done
	LN
}

function make_log_names
{
	if [ $node -ne -1 ]
	then
		if [[ ! -v ID_DB ]]
		then
			error "set_db must be used with -node"
			exit 1
		fi

		db=$ID_DB

		if [ x"$server" != x ]
		then
			error "-node & -server cannot be used together."
			exit 1
		fi

		server=$(printf "srv%s%02d" $ID_DB $node)
	elif [[ x"$server" == x && x"$ID_DB" != x ]]
	then
		db=$ID_DB
		server=$(printf "srv%s01" $ID_DB)
	fi

	[ $date == undef ] && set_to_last_date || true

	if [ $time == undef ]
	then
		debug "ls -rt ${PLELOG_ROOT}/$date/stats/*${server}*${title}shmstat.log"
		last_log_file=$(ls -rt ${PLELOG_ROOT}/$date/stats/*${server}*${title}shmstat.log 2>/dev/null)
		[ x"$last_log_file" = x ] && error "File not found in ${PLELOG_ROOT}/$date" && exit 1

		IFS=_ read time server title rem<<<${last_log_file##*/}
		info "set time to   $time"
		info "set server to $server"
		info "set title to  $title"
		LN

		log_shm=$(ls -rt ${PLELOG_ROOT}/$date/stats/${time}_${server}*shmstat.log)
		log_mem=$(ls -rt ${PLELOG_ROOT}/$date/stats/${time}_${server}*memstat.log)
		log_swap=$(ls -rt ${PLELOG_ROOT}/$date/stats/${time}_${server}*swapstat.log)
	fi

	if [ $log_shm == undef ]
	then
		log_shm=${PLELOG_ROOT}/$date/stats/${time}_${server}${title}shmstat.log
		log_mem=${PLELOG_ROOT}/$date/stats/${time}_${server}${title}memstat.log
		log_swap=${PLELOG_ROOT}/$date/stats/${time}_${server}${title}swapstat.log
	fi

	[ x"$server" == x ] && server=$(cut -d_ -f2 <<< $log_mem)

	exit_if_file_not_exists $log_shm
	exit_if_file_not_exists $log_mem

	if [ $clear_log == yes ]
	then
		info "Clear logs :"
		exec_cmd "> $log_shm"
		exec_cmd "> $log_mem"
		exec_cmd "> $log_swap"
		timing 10
	fi
}

#	============================================================================
#	MAIN
#	============================================================================
if [ $show_log_only == yes ]
then
	set_to_last_date
	show_formatted_logs
	exit 0
fi

if ! command_exists gnuplot
then
	error "gnuplot n'est pas installé ou pas dans PATH."
	exit 1
fi

make_log_names

if [ $db != undef ] && cfg_exists $db use_return_code 1>/dev/null 2>&1
then
	cfg_load_node_info $db 1
	if [[ $(cfg_max_nodes $db) -eq 2 ]] || [[ $cfg_standby != none && $skip_standby == no ]]
	then
		launch_second_script=yes
	fi
fi

#	Lecture de l'heure de début des mesures
typeset -r	start_time=$(sed -n "2p" $log_shm | cut -d' ' -f1)

# Lecture de la seconde mesure (ligne 3 donc) pour déterminer le refresh rate.
typeset -r	second_time=$(sed -n "3p" $log_shm | cut -d' ' -f1)

# Fréquence de rafraîchissement :
debug "start_time  = $start_time"
debug "second_time = $second_time"
typeset		refresh_rate=$(compute \
				 "($(time_to_secs $second_time) - $(time_to_secs $start_time))*2")

# boxes lines linespoints points impulses histeps
# ok : points, histeps, linespoints
typeset -r with="linespoints pointinterval $(( (5*60) / refresh_rate ))"

typeset	-r	fmt_time="%H:%M:%S"

typeset plot_cmds=/tmp/memory.plot.$$
#https://www2.uni-hamburg.de/Wiss/FB/15/Sustainability/schneider/gnuplot/colors.htm

typeset -i line_to_skip=1

typeset graph_title=$title
[ "${graph_title%_}" == "global" ] && graph_title="Start at $time (Points interval : 5mn)"

typeset -r stats_info=${PLELOG_ROOT}/$date/stats/stats_info.txt
if [ $loop == yes ]
then
	cmds="$(printf "pause $refresh_rate\nreread\nreplot\n")"
else
	cmds="pause -1"
fi

typeset -r stats_markers=$PLESTATS_PATH/stats_info.txt
typeset labels
if [ -f $stats_markers ]
then
	info "Fabrication des labels..."
	typeset -i	loop=0
	typeset -i	trans=400
	typeset	-ri	offset_trans=200
	while read action what tt
	do
		loop=loop+1
		w=unset
		case "$what" in
			grid_installation)		w="GI" ;;
			oracle_installation)	w="Orcl" ;;
			create_*)				w="${what##*_}" ;;
			*)	error "'$what' unknow !!!"	;;
		esac
		labels=$(printf "$labels\nset label \"$action $w\" at \"$tt\",$trans")
		[ $(( loop % 2 )) -eq 0 ] && trans=$(( trans + offset_trans ))
	done<$stats_markers
fi

typeset	-r	range_max_lines=$(( (range_mn * 60) / refresh_rate ))

cat << EOS > $plot_cmds
set key autotitle columnhead
set grid
set datafile separator " "
set term qt title '${server%_} : ${graph_title}' size 944,512
set title '${server%_} : ${graph_title}'
set format x '$fmt_time'
set timefmt '$fmt_time'
set xdata time
set xlabel 'Time'
set xtic rotate by -45
set ylabel 'Mega bytes (Mb)'
$labels
plot	\
	"< tail -n$range_max_lines $log_mem"	using 1:2 title 'Mem Max'	with lines		lt rgb "red",	\
	"< tail -n$range_max_lines $log_mem"	using 1:3 title 'Mem Used'	with ${with}	lt rgb "orange",\
\
	"< tail -n$range_max_lines $log_shm"	using 1:2 title 'SHM Max'	with lines		lt rgb "brown",	\
	"< tail -n$range_max_lines $log_shm"	using 1:3 title 'SHM Used'	with ${with}	lt rgb "green",	\
\
	"< tail -n$range_max_lines $log_swap"	using 1:3 title 'Swap Used'	with ${with}	lt rgb "blue"
$cmds
EOS

line_separator
cat $plot_cmds
LN

line_separator
info "Refresh rate $(fmt_seconds $refresh_rate)"
info "Range : ( ${range_mn}mn * 60 ) / ${refresh_rate}s = ${range_max_lines} last lines read from input file."
LN

info "Load file    $log_shm"
info "Load file    $log_mem"
info "Load file    $log_swap"
LN

line_separator
if [ $launch_second_script == yes ]
then
	if [ $cfg_standby == none ]
	then
		if [ $node -eq 2 ]
		then
			info "RAC lanch second script on second server."
			~/plescripts/stats/memplot.sh -node=2 &
			LN
		fi
	else # pas testé, mais ne fonctionnerra pas !
		info "Dataguard lanch second script on second server $cfg_standby."
		fake_exec_cmd "ID_DB=$cfg_standby ~/plescripts/stats/memplot.sh -skip_standby &"
		ID_DB=$cfg_standby ~/plescripts/stats/memplot.sh -skip_standby &
		LN
	fi
fi

line_separator
gnuplot $plot_cmds
info "gnuplot return $?"
rm $plot_cmds

exit 0
#rm -rf nohup.out >/dev/null 2>&1
#nohup gnuplot $plot_cmds &
#info "My pid is $!"
