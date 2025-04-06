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

generate_exports_content () {
	: ${EXPORT_ROOT?}
	if ! [ "$NO_DEFAULT_EXPORT" ]; then
		local opts
		if [ "$AUTOEXPORT_ALL" ] && [ "$AUTOEXPORT_ENABLE_WRITE" ]; then
			opts="rw"
		else
			opts="ro"
		fi
		opts="${opts},all_squash,fsid=root,no_subtree_check"
		if [ "$AUTOEXPORT_ALL" ]; then
			opts="${opts},crossmnt"
		fi
		echo "${EXPORT_ROOT} -${opts}${EXPORT_ROOT_EXTRA:+,$EXPORT_ROOT_EXTRA} ${EXPORT_ROOT_HOSTS:-*}"
	fi
	local vars=$(awk 'END { for (n in ENVIRON) if (n ~ /^EXPORTS/) print n }' /dev/null | sort -n)
	if [ "${vars:+1}" ]; then
		printenv $vars | envsubst '$EXPORT_ROOT'
	fi
}

run_server () {
	echo "Starting nfs server..."

	echo "Current /etc/exports:"
	nl -b a /etc/exports
	exportfs -rav

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
		${NFSD_EXTRA_OPTS} \
		|| exit

	debug_nfsd_state

	rpc.mountd \
		--foreground \
		--debug all \
		--no-nfs-version 3 \
		--nfs-version 4 \
		${MOUNTD_EXTRA_OPTS} \
		|| exit
}

main () {
	: ${EXPORT_ROOT:="/srv"}
	export EXPORT_ROOT

	# check if exports is empty (except for comments)
	if ! [ -e /etc/exports ] || [ $(grep -Evxc '\s*(#.*)?' /etc/exports) -le 0 ]; then
		generate_exports_content > /etc/exports
	fi

	# run command if provided
	[ $# -gt 0 ] && exec "$@"

	nfsd_prereqs_check

	run_server
}

# put this function last since it messes with syntax highlighting
has_capability () {
	local check_cap=$1
	local eff_caps=0x$(grep ^CapEff: /proc/self/status | cut -f 2)
	[ $(( $eff_caps & ( 1 << $check_cap ) )) -gt 0 ]
	return $?
}

main "$@"
