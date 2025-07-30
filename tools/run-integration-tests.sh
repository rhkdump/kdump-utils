#!/bin/bash

set -ex

[[ -d ${0%/*} ]] && cd "${0%/*}"/../

fedora_version=${1:-40}
mirror=${2:-https://mirrors.tuna.tsinghua.edu.cn/fedora}
[[ $fedora_version == rawhide ]] && mirror=https://mirrors.sjtug.sjtu.edu.cn/fedora/linux

dist_abbr=.fc$fedora_version

VERSION=$(rpmspec -q --queryformat "%{VERSION}" kdump-utils.spec)
SRC_ARCHIVE=kdump-utils-$VERSION.tar.gz
if ! git archive --format=tar.gz -o "$SRC_ARCHIVE" --prefix="kdump-utils-$VERSION/" HEAD; then
	echo "Failed to create kdump-utils source archive"
	exit 1
fi

if ! rpmbuild -ba -D "dist $dist_abbr" -D "_sourcedir $(pwd)" -D "_builddir $(pwd)" -D "_srcrpmdir $(pwd)" -D "_rpmdir $(pwd)" kdump-utils.spec; then
	echo "Failed to build kdump-utils rpm"
	exit 1
fi

arch=$(uname -m)
rpm_name=$(rpmspec -D "dist $dist_abbr" -q --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' kdump-utils.spec)
rpm_path="$(pwd)/${arch}/${rpm_name}.rpm"
if [[ ! -f $rpm_path ]]; then
	echo "Failed to find built kdump-utils rpm ($rpm_path doesn't eixst)"
fi

cd tests && tmt --context distro="fedora-${fedora_version}" run --environment CUSTOM_MIRROR="$mirror" --environment KDUMP_UTILS_RPM="$rpm_path" -a provision -h virtual -i fedora:"$fedora_version" plans --name lvm2_thinp
