#!/bin/bash

set -ex

[[ -d ${0%/*} ]] && cd "${0%/*}"/../

fedora_version=${1:-40}
mirror=${2:-https://mirrors.tuna.tsinghua.edu.cn/fedora}
[[ $fedora_version == rawhide ]] && mirror=https://mirrors.sjtug.sjtu.edu.cn/fedora/linux

if ! rpm_path=$(./tools/build-rpm.sh "$fedora_version"); then
	echo "Failed to build kdump-utils rpm"
	exit 1
fi

tmt_run_env=(--environment CUSTOM_MIRROR="$mirror" --environment KDUMP_UTILS_RPM="$rpm_path" --environment RESOURCE_URL=https://gitlab.cee.redhat.com/kernel-qe/kernel/-/raw/master/kdump/internal/internal_resources.sh --environment AUTO_CONFIG=pek)

tmt_context=(--context distro="fedora-${fedora_version}")
cd tests && tmt "${tmt_context[@]}" run "${tmt_run_env[@]}" -a provision -h virtual -i fedora:"$fedora_version" plans --name lvm2_thinp

if [[ $fedora_version == rawhide ]]; then
	cd ../kernel-tests-plans
	tmt_context+=(--context install_built_rpm=yes)
	tmt "${tmt_context[@]}" run \
		"${tmt_run_env[@]}" \
		-a provision -h virtual -c system -i fedora:"$fedora_version" plans --name nfs_ovs

	# Run test plans for CoreOS
	for _stream in stable testing next; do
		core_os_stream="fedora-coreos-${_stream}"
		tmt_context[1]="distro=${core_os_stream}"
		tmt_context+=(--context variant=CoreOS)
		tmt "${tmt_context[@]}" run \
			"${tmt_run_env[@]}" \
			-a provision -h virtual -c system -i "${core_os_stream}" plans --name "local|nfs$"
	done
fi
