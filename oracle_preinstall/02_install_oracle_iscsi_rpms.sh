#!/bin/bash

#	ts=4 sw=4

. ~/plescripts/plelib.sh
EXEC_CMD_ACTION=EXEC

line_separator
info "Install Oracle rdbms rpm"
exec_cmd yum -y $oracle_rdbms_rpm
LN

line_separator
info "iscsi packags"
exec_cmd yum -y install iscsi-initiator-utils
LN

line_separator
info "git"
exec_cmd yum -y install git
LN
# Pour el6 ajouter lsscsi
