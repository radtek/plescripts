#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/dblib.sh
. ~/plescripts/gilib.sh
. ~/plescripts/usagelib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

typeset -r ME=$0

typeset	-r	orcl_release="$(read_orcl_release)"

typeset db=undef
typeset pdb=undef
typeset from_pdb=default
if [ $orcl_release == 12.1 ]
then
	typeset		wallet=yes
elif test_if_cmd_exists crsctl
then # Impossible de démarrer la base avec le wallet.
	typeset		wallet=no
else # Sur FS pas de problème.
	typeset		wallet=yes
fi
typeset	sampleSchema=no
typeset is_seed=no
typeset admin_user=pdbadmin
typeset admin_pass=$oracle_password

typeset	log=yes

add_usage "-db=name"			"Database name."
add_usage "-pdb=name"			"PDB name."
add_usage "[-sampleSchema=$sampleSchema]"	"yes|no"
add_usage "[-is_seed]"			"Create seed pdb."
add_usage "[-from_pdb=name]"	"Clone from pdb 'name'"
add_usage "[-wallet=$wallet]"	"yes|no yes : Use Wallet Manager for pdb connection."
add_usage "[-admin_user=$admin_user]"
add_usage "[-admin_pass=$admin_pass]"
add_usage "[-nolog]"

typeset -r str_usage=\
"Usage :
$ME
$(print_usage)
"

while [ $# -ne 0 ]
do
	case $1 in
		-emul)
			EXEC_CMD_ACTION=NOP
			shift
			;;

		-db=*)
			db=$(to_lower ${1##*=})
			shift
			;;

		-pdb=*)
			pdb=$(to_lower ${1##*=})
			shift
			;;

		-sampleSchema=*)
			sampleSchema=$(to_lower ${1##*=})
			shift
			;;

		-from_pdb=*)
			from_pdb=$(to_lower ${1##*=})
			shift
			;;

		-is_seed)
			is_seed=yes
			shift
			;;

		-wallet=*)
			wallet=$(to_lower ${1##*=})
			shift
			;;

		-admin_user=*)
			admin_user=${1##*=}
			shift
			;;

		-admin_pass=*)
			admin_pass=${1##*=}
			shift
			;;

		-nolog)
			log=no
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

[ $log == yes ] && ple_enable_log || true

script_banner $ME $*

must_be_user oracle

exit_if_param_undef db	"$str_usage"
exit_if_param_undef pdb	"$str_usage"

exit_if_param_invalid	wallet			"yes no"	"$str_usage"
exit_if_param_invalid	sampleSchema	"yes no"	"$str_usage"

[ $log == yes ] && script_start || true

if test_if_cmd_exists olsnodes
then
	typeset -r crs_used=yes
else
	typeset -r crs_used=no
fi

exit_if_database_not_exists $db

exit_if_ORACLE_SID_not_defined

function clone_pdb_pdbseed
{
	function ddl_create_pdb
	{
		set_sql_cmd "whenever sqlerror exit 1;"
		set_sql_cmd "create pluggable database $pdb admin user $admin_user identified by $admin_pass;"
	}
	sqlplus_cmd "$(ddl_create_pdb)"
	[ $? -ne 0 ] && exit 1 || true
}

# $1 pdb name
function clone_from_pdb
{
	# $1 pdb name
	function ddl_clone_from_pdb
	{
		set_sql_cmd "whenever sqlerror exit 1;"
		if [ $dataguard == yes ]
		then
			# Sur un Dataguard si le PDB est RW alors la synchro est HS
			# Il faut que le PDB soit RO pour être clonable : BUG or not BUG ??
			# Testé sur la 12.2 c'est la même chose.
			set_sql_cmd "alter pluggable database $1 close immediate instances=all;"
			set_sql_cmd "alter pluggable database $1 open read only instances=all;"
		fi
		set_sql_cmd "create pluggable database $pdb from $1;"
		if [ $dataguard == yes ]
		then
			set_sql_cmd "alter pluggable database $1 close immediate instances=all;"
			set_sql_cmd "alter pluggable database $1 open instances=all;"
		fi
	}
	info "Clone $pdb from $1"
	if [ $dataguard == yes ]
	then
		warning "Dataguard bug : $1 must be reopen RO"
		LN
	fi
	sqlplus_cmd "$(ddl_clone_from_pdb $1)"
	[ $? -ne 0 ] && exit 1 || true
}

# Primary database : no parameter
# Physical database : -physical
function pdb_seed_ro_and_save_state
{
	#	Sur un dataguard le PDB doit être ouvert pour être clonable.
	#	Il sera donc un RO comme PDB$SEED.
	#	Il n'a pas de services, donc son état doit être sauvegardé sur toutes
	#	les bases d'un dataguard.
	set_sql_cmd "alter pluggable database $pdb close instances=all;"
	set_sql_cmd "whenever sqlerror exit 1;"
	if [ "$1" != -physical ]
	then
		set_sql_cmd "alter pluggable database $pdb open read write instances=all;"
		set_sql_cmd "alter pluggable database $pdb close instances=all;"
	fi
	set_sql_prompt "Open seed pdb $pdb RO and save state"
	set_sql_cmd "alter pluggable database $pdb open read only instances=all;"
	set_sql_cmd "alter pluggable database $pdb save state instances=all;"
}

function create_database_trigger_no_crs
{
	info "Create trigger open_stby_pdbs_ro"
	sqlplus_cmd "$(set_sql_cmd "@$HOME/plescripts/db/sql/create_trigger_open_stby_pdbs_ro.sql")"
	LN

	typeset pdbconn="sys/$oracle_password@localhost:1521/$pdb as sysdba"
	info "Create trigger start_pdb_services"
	sqlplus_cmd_with "$pdbconn"  "$(set_sql_cmd "@$HOME/plescripts/db/sql/create_trigger_start_pdb_services.sql")"
	LN
}

# return 0 if RAC One Node, else 1
function is_rac_one_node
{
	srvctl status database -db $db| grep -q "Online relocation: INACTIVE"
}

function create_pdb_services
{
	if [[ $crs_used == no ]]
	then
		line_separator
		create_database_trigger_no_crs
		LN
	fi

	line_separator
	info "Create services"
	if [[ $dataguard == yes && ${#physical_list[@]} -ne 0 ]]
	then
		for (( i=0; i < ${#physical_list[@]}; ++i ))
		do
			add_dynamic_cmd_param "-db=$primary"
			add_dynamic_cmd_param "-pdb=$pdb"
			add_dynamic_cmd_param "-standby=${physical_list[i]}"
			add_dynamic_cmd_param "-standby_host=${stby_server_list[i]}"
			exec_dynamic_cmd "./create_srv_for_dataguard.sh"
			LN
		done
	else
		if [ $dataguard == yes ]
		then
			warning "Dataguard configured but no physical standby"
			LN
		fi

		if [ $gi_count_nodes -eq 1 ]
		then
			exec_cmd ./create_srv_for_single_db.sh -db=$db -pdb=$pdb
		elif is_rac_one_node
		then
			exec_cmd ./create_srv_for_rac_one_node_db.sh -db=$db -pdb=$pdb
		else
			typeset poolName="$(srvctl config database -db $db	|\
								grep "^Server pools:" | awk '{ print $3 }')"
			exec_cmd ./create_srv_for_rac_db.sh	\
									-db=$db -pdb=$pdb -poolName=$poolName
		fi
	fi
}

# Si un PDB est clonée depuis un PDB existant, il faut supprimer tous les
# services du pdb existant qui sont dans le PDB cloné.
function sqlcmd_remove_services_from_cloned_pdb
{
	set_sql_cmd "alter pluggable database $pdb close immediate instances=all;"
	set_sql_cmd "alter pluggable database $pdb open read write instances=all;"
	set_sql_cmd "alter session set container=$pdb;"
	echo "set serveroutput on"
	echo "begin"
	echo "    for s in ( select name from all_services where name != '$(to_lower $pdb)' )"
	echo "    loop"
	echo "        dbms_output.put_line( 'Remove service : '||s.name );"
	echo "        dbms_service.delete_service( s.name );"
	echo "    end loop;"
	echo "end;"
	echo "/"
}

function create_wallet
{
	line_separator
	exec_cmd "~/plescripts/db/add_sysdba_credential_for_pdb.sh -db=$db -pdb=$pdb"
	if [ $dataguard == yes ]
	then
		for (( i=0; i < ${#physical_list[@]}; ++i ))
		do
			exec_cmd "ssh ${stby_server_list[i]}	\
				'. .bash_profile;	\
				~/plescripts/db/add_sysdba_credential_for_pdb.sh	\
									-db=${physical_list[i]} -pdb=$pdb'"
			LN
		done
	fi

	if [ $orcl_release == 12.2 ] && test_if_cmd_exists crsctl
	then
		warning "Database cannot start with wallet enable."
		LN
	fi
}

[ $is_seed == yes ] && wallet=no || true

typeset	-r dataguard=$(dataguard_config_available)

if [ $dataguard == yes ]
then
	if [[ $gi_count_nodes -gt 1 ]]
	then
		error "RAC + Dataguard not supported."
		exit 1
	fi

	typeset -r primary="$(read_primary_name)"
	if [ "$primary" != "$db" ]
	then
		error "db=$db, primary name is $primary"
		error "Execute script on primary database."
		LN
		exit 1
	fi

	typeset -a physical_list
	typeset -a stby_server_list
	load_stby_database
fi

info "On database $db create pdb $pdb"
if [ $dataguard == yes ]
then
	info "Physical standby : ${physical_list[*]}"
	info "Servers          : ${stby_server_list[*]}"
fi
LN

line_separator
[ $from_pdb == default ] && clone_pdb_pdbseed || clone_from_pdb $from_pdb
LN

for stby in ${physical_list[*]}
do
	exec_cmd "dgmgrl -silent sys/$oracle_password 'show database ${stby}'"
	LN
done

if [ $from_pdb != default ]
then
	info "Remove services cloned from $from_pdb on $pdb"
	sqlplus_cmd "$(sqlcmd_remove_services_from_cloned_pdb)"
	LN
fi

if [ $is_seed == yes ]
then
	info "Open RO $pdb and save state."
	sqlplus_cmd "$(pdb_seed_ro_and_save_state)"
	LN
else
	function open_pdb_and_save_state
	{
		set_sql_cmd "alter pluggable database $pdb open instances=all;"
		set_sql_cmd "alter pluggable database $pdb save state;"
	}
	info "Open RW $pdb and save state."
	sqlplus_cmd "$(open_pdb_and_save_state)"
	LN

	create_pdb_services
fi

if [[ $dataguard == yes && ${#physical_list[*]} -ne 0 ]]
then
	function add_temp_tbs_to
	{
		set_sql_cmd "alter session set container=$1;"
		set_sql_cmd "alter tablespace temp add tempfile;"
	}

	line_separator
	info "12c : temporary tablespace not created on standby."
	for stby_name in ${physical_list[*]}
	do
		sqlplus_cmd_with sys/$oracle_password@$stby_name as sysdba	\
											"$(add_temp_tbs_to $pdb)"
		if [ $is_seed == yes ]
		then
			sqlplus_cmd_with sys/$oracle_password@$stby_name as sysdba	\
								"$(pdb_seed_ro_and_save_state -physical)"
		fi
		LN
	done
fi

[ $wallet == yes ] && create_wallet || true

if [ $sampleSchema == yes ]
then
	info "Create sample schemas on $pdb"
	exec_cmd ~/plescripts/db/create_sample_schemas.sh	\
						-db=$db							\
						-pdb=$pdb
	LN
fi

line_separator
typeset -r violations=\
"select
	name		\"PDB Name\"
,	count(*)	\"PDB Violations\"
from
	pdb_plug_in_violations
where
	status	!= 'RESOLVED'
and	name	= upper( '$pdb' )
group by
	name
;"

info "$pdb violations"
sqlplus_print_query "$violations"
LN

[ $log == yes ] && script_stop ${ME##*/} || true
