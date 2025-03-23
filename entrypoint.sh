#!/bin/sh
set -e

# from include/linux/capability.h
CAP_SYS_MODULE=16
CAP_SYS_ADMIN=21

nfsd_prereqs_check () {
	# check if nfsd module is not loaded
	if [ -z "$(awk '$1 == "nfsd"' /proc/modules)" ]; then
		echo "ERROR: nfsd module not loaded on the host kernel." >&2
		has_capability $CAP_SYS_MODULE || {
			echo \
				"Load it using 'modprobe nfsd' or allow the container to attempt loading the module" \
				"by granting the CAP_SYS_MODULE privilege using '--cap-add SYS_MODULE' or '--privileged'." \
				>&2
			exit 1
		}
		# TODO: find and insert module
	fi

	# check if /proc/fs/nfsd is not mounted
	if [ -z "$(awk '$5 == "/proc/fs/nfsd"' /proc/self/mountinfo)" ]; then
		has_capability $CAP_SYS_ADMIN || {
			echo \
				"ERROR: /proc/fs/nfsd not mounted and missing CAP_SYS_ADMIN required to mount." \
				"Try using '--cap-add SYS_ADMIN' or '--privileged'." \
				>&2
			exit 1
		}
		mkdir -p /proc/fs/nfsd
		mount -t nfsd nfsd /proc/fs/nfsd
	fi
}

debug_nfsd_state () {
	local t
	[ -r /proc/fs/nfsd/threads ] || {
		echo "ERROR: Unable to access nfsd state" >&2
		return 1
	}
	t=$(cat /proc/fs/nfsd/threads)
	if [ $t -gt 0 ]; then
		echo "nfsd is running: threads $t"
	else
		echo "nfsd is stopped"
	fi
}

main () {
	[ "$1" = "rpc.nfsd" ] && shift || exec "$@"

	nfsd_prereqs_check

	# TODO: handle exports

	# stop nfsd on exit
	trap '
		rpc.nfsd --debug 0
		rv=$?
		debug_nfsd_state
		exit $rv
	' EXIT

	rpc.nfsd \
		--debug \
		--no-nfs-version 3 \
		--nfs-version 4 \
		"$@" || exit

	debug_nfsd_state

	sleep inf
}

# put this function last since it messes with syntax highlighting
has_capability () {
	local check_cap=$1
	local eff_caps=0x$(grep ^CapEff: /proc/self/status | cut -f 2)
	[ $(( $eff_caps & ( 1 << $check_cap ) )) -gt 0 ]
	return $?
}

main "$@"
