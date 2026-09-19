# -*-eselect-*-  vim: ft=eselect
# Copyright (c) 2005-2013 Gentoo Foundation
#
# This file is part of the 'eselect' tools framework.
#
# eselect is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation, either version 2 of the License, or (at your option) any later
# version.
#
# eselect is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# eselect.  If not, see <http://www.gnu.org/licenses/>.

# This library is for managing a common binary symlink like /bin/sh
# or /usr/bin/pinentry. To use it, you need to set the following
# variables:
#
# SYMLINK_PATH is the name of symlink being created, e.g. "/bin/sh".
# The path should be absolute, without EPREFIX (it will be added).
#
# SYMLINK_TARGETS is the list (bash array) of targets being available.
# The paths should be relative to ${SYMLINK_PATH}. Only basenames
# of the targets will be displayed to user. Best (preferred) targets
# should go earlier on the list.
#
# SYMLINK_DESCRIPTION is the human-friendly name of the symlink, e.g.
# "POSIX shell". It will be used in the context of "implementation"
# or "symlink". Defaults to basename of ${SYMLINK_PATH}.
#
# SYMLINK_CRUCIAL should be set to a non-null value if existence of no
# targets should trigger a fatal error rather than silent symlink
# removal.

# Version: 0.1.1
# Maintainer: mgorny@gentoo.org
# Based on the work of:
# - Erik Hahn; bug #214817
# - Samuli Suominen <ssuominen@gentoo.org>; eselect-pinentry

## Global variables ##

if [[ ! ${SYMLINK_PATH} ]]; then
	die "SYMLINK_PATH needs to be set by eselect module."
fi

if [[ ! ${SYMLINK_TARGETS[@]} ]]; then
	die "SYMLINK_TARGETS need to be set by eselect module."
fi

: ${SYMLINK_DESCRIPTION:-${SYMLINK_PATH##*/}}

## Functions ##

# find a list of symlink targets, best first
find_targets() {
	local basedir=${SYMLINK_PATH%/*}
	TARGETS=()

	local t
	for t in "${SYMLINK_TARGETS[@]}"; do
		if [[ -x ${EROOT}${basedir}/${t} ]]; then
			TARGETS+=( ${t} )
		fi
	done
}

# set the pinentry symlink
set_symlinks() {
	local target="${1}" targets
	local basedir=${SYMLINK_PATH%/*}

	[[ ! -L ${EROOT}${SYMLINK_PATH} && -e ${EROOT}${SYMLINK_PATH} ]] && \
		die -q "${EROOT}${SYMLINK_PATH} is not a symlink!"

	if is_number "${target}" && [[ ${target} -ge 1 ]]; then
		local TARGETS

		find_targets
		target=${TARGETS[target-1]}
	elif [[ ! -x ${EROOT}${basedir}/${target} ]]; then
		# try basename matching
		local TARGETS t
		find_targets

		for t in "${TARGETS[@]}"; do
			if [[ ${t##*/} == ${target} ]]; then
				target=${t}
				break
			fi
		done
	fi

	if [[ -x ${EROOT}${basedir}/${target} ]]; then
		local tmpf=${EROOT}${SYMLINK_PATH}.new
		# we could use 'ln -f' to directly replace the symlink
		# but 'mv' is an atomic operation so it should be more fault-proof

		ln -s "${target}" "${tmpf}" || \
			die -q "Unable to create temporary symlink"
		if ! mv "${tmpf}" "${EROOT}${SYMLINK_PATH}"; then
			rm -f "${tmpf}" # cleanup
			die -q "Unable to replace ${EROOT}${SYMLINK_PATH} symlink with ${target}"
		fi
	else
		die -q "Target '${target}' doesn't appear to be valid!"
	fi
}

### show action ###

describe_show() {
	echo "Show the current ${SYMLINK_DESCRIPTION} implementation"
}

do_show() {
	[[ ${@} ]] && die -q "Too many parameters"

	write_list_start "Current ${SYMLINK_DESCRIPTION} implementation:"
	if [[ -L ${EROOT}${SYMLINK_PATH} ]]; then
		local t=$(readlink "${EROOT}${SYMLINK_PATH}")
		write_kv_list_entry "${t##*/}" ""
	elif [[ -e ${EROOT}${SYMLINK_PATH} ]]; then
		write_kv_list_entry "(not a symlink)" ""
	else
		write_kv_list_entry "(unset)" ""
	fi
}

### list action ###

describe_list() {
	echo "List available ${SYMLINK_DESCRIPTION} implementations"
}

do_list() {
	[[ ${@} ]] && die -q "Too many parameters"

	local i TARGETS
	find_targets

	write_list_start "Available ${SYMLINK_DESCRIPTION} implementations:"
	if [[ ${TARGETS[@]} ]]; then
		local curr=$(readlink "${EROOT}${SYMLINK_PATH}")

		for (( i = 0; i < ${#TARGETS[@]}; i++ )) ; do
			[[ ${TARGETS[${i}]##*/} == ${curr##*/} ]] && \
				TARGETS[${i}]+=" $(highlight '*')"
		done
		write_numbered_list "${TARGETS[@]##*/}"
	else
		write_kv_list_entry "(none found)" ""
	fi
}

### set action ###

describe_set() {
	echo "Set a new ${SYMLINK_DESCRIPTION} implementation"
}

describe_set_options() {
	echo "target : Target name, number (from 'list' action) or path"
}

describe_set_parameters() {
	echo "<target>"
}

do_set() {
	if [[ ${#} != 1 ]]; then
		die -q "set takes exactly one parameter"
	else
		set_symlinks "${1}"
	fi
}

### update action ###

describe_update() {
	echo "Automatically update the ${SYMLINK_DESCRIPTION} implementation"
}

describe_update_options() {
	echo "--if-unset : do not override existing implementation"
}

do_update() {
	[[ ${1} == ifunset ]] && set -- --if-unset "${@:2}"

	if [[ ( ${1} && ${1} != '--if-unset' ) || ${2} ]]
	then
		die -q "usage error"
	fi

	if [[ ${1} == '--if-unset' && -L ${EROOT}${SYMLINK_PATH} \
			&& -x ${EROOT}${SYMLINK_PATH} ]]
	then
		return
	fi

	local TARGETS
	find_targets

	if [[ ! ${TARGETS[@]} ]]; then
		if [[ ${SYMLINK_CRUCIAL} ]]; then
			die "No targets for ${EROOT}${SYMLINK_PATH}, system likely broken."
		else
			rm -f "${EROOT}${SYMLINK_PATH}"
		fi
	else
		set_symlinks "${TARGETS[0]}"
	fi
}

# vim:ts=4:sts=4:sw=4
