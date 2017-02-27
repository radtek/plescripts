#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/gilib.sh
. ~/plescripts/dblib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0
typeset -r str_usage=\
"Usage : $ME
	-db=name  Nom de la base à supprimer.
"

typeset db=undef

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			shift
			;;

		-db=*)
			db=$(to_upper ${1##*=})
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

ple_enable_log

exit_if_param_undef db	"$str_usage"

exit_if_database_not_exists $db

function error_msg_on_script_failed
{
	LN
	info "Si la base n'est pas démarrée, démarré là."
	LN

	info "Sinon :"
	info "Problème survenant lors de problèmes de synchronisation NTP en"
	info "particulier sur les RAC."
	LN
	info "1) Vérifier la synchro NTP puis recommencer."
	info "2) Si l'ORACLE_HOME est sur OCFS2 faire un fsck.ocfs2 sur tous les nœuds."
	LN

	info "Si 1 et 2 sont OK, alors :"
	info "Si le nom de la base $db et le mot de passe sys $oracle_password sont correctes,"
	info "exécuter avec le compte root :"
	info "$ cd ~/plescripts/db"
	info "$ ./remove_all_files_for_db.sh -db=$db"
	LN
}

info "Check DBFS"
typeset dbfs=no
while read res_name
do
	[ x"$res_name" == x ] && continue || true

	[ $dbfs == no ] && dbfs=yes || true

	pdbName=$(cut -d. -f2<<<$res_name)
	info "Drop dbfs for pdb $pdbName"
	exec_cmd -c  "~/plescripts/db/dbfs/drop_dbfs.sh -db=$db -pdb=$pdbName	\
													-skip_drop_user</dev/tty"
	LN
done<<<"$(crsctl stat res -t | grep -E ".*\.dbfs$")"
if [ $dbfs == no ]
then
	info "no dbfs to remove."
	LN
fi

line_separator
info "Drop wallet."
exec_cmd ~/plescripts/db/wallet/delete_all_credentials.sh
exec_cmd ~/plescripts/db/wallet/drop_wallet.sh
LN

line_separator
info "Delete services :"
exec_cmd "~/plescripts/db/drop_all_services.sh -db=$db"
LN

trap '[ "$?" -ne 0 ] && error_msg_on_script_failed' EXIT

line_separator
info "Delete database :"
LN

add_dynamic_cmd_param "-deleteDatabase"
add_dynamic_cmd_param "    -sourcedb       $db"
add_dynamic_cmd_param "    -sysDBAUserName sys"
add_dynamic_cmd_param "    -sysDBAPassword $oracle_password"
add_dynamic_cmd_param "    -silent"
exec_dynamic_cmd dbca
LN

if ps -ef|grep -q [p]mon_$db
then
	error "dbca failed."
	LN
	info "L'affichage de dbca et son code retour peuvent laissé croire"
	info "que tout c'est bien passé sauf que parfois dbca redémarre (cf log)"
	LN
	exit 1
fi

typeset -r rm_1="rm -rf $ORACLE_BASE/cfgtoollogs/dbca/${db}*"
typeset -r rm_2="rm -rf $ORACLE_BASE/diag/rdbms/$(to_lower $db)"
typeset -r rm_3="rm -rf $ORACLE_BASE/admin/$db"
typeset -r rm_4="rm -rf $ORACLE_HOME/dbs/*${db}*"

line_separator
info "Purge des répertoires :"
LN
exec_cmd "$rm_1"
execute_on_other_nodes "$rm_1"
LN
exec_cmd "$rm_2"
execute_on_other_nodes "$rm_2"
LN
exec_cmd "$rm_3"
execute_on_other_nodes "$rm_3"
LN
exec_cmd "$rm_4"
execute_on_other_nodes "$rm_4"
LN

if [ x"$gi_node_list" != x ]
then	#	Sur les RACs les nom des instances ont été ajoutés.
	typeset -r clean_oratab_cmd1="sed  '/${db:0:8}_\{,1\}[0-9].*/d' /etc/oratab > /tmp/oracle_oratab"
	typeset -r clean_oratab_cmd2="cat /tmp/oracle_oratab > /etc/oratab && rm /tmp/oracle_oratab"

	line_separator
	info "Remove instance name from /etc/oratab."
	exec_cmd "$clean_oratab_cmd1"
	exec_cmd "$clean_oratab_cmd2"
	LN

	execute_on_other_nodes "$clean_oratab_cmd1"
	execute_on_other_nodes "$clean_oratab_cmd2"
	LN
fi

if $(test_if_cmd_exists olsnodes)
then
	line_separator
	info "Clean up ASM :"
	exec_cmd -c "sudo -u grid -i asmcmd rm -rf DATA/$db"
	exec_cmd -c "sudo -u grid -i asmcmd rm -rf FRA/$db"
	LN
fi

info "${GREEN}Done.${NORM}"
LN
