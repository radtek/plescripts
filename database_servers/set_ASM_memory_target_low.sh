#!/bin/bash
# vim: ts=4:sw=4

. ~/plescripts/plelib.sh
. ~/plescripts/dblib.sh
. ~/plescripts/global.cfg
EXEC_CMD_ACTION=EXEC

function sqlcmd_set_low_memory
{
	set_sql_cmd "show parameter memory_target;"
	set_sql_cmd "alter system set \"_asm_allow_small_memory_target\"=true scope=spfile sid='*';"
	if [[ x"$hack_asm_memory" != x && "$hack_asm_memory" != "0" ]]
	then
		set_sql_cmd "alter system set memory_target=$hack_asm_memory scope=spfile sid='*';"
	fi
}

sqlplus_asm_cmd "$(sqlcmd_set_low_memory)"
LN
