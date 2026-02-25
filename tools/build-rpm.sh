#!/bin/bash
#
# Build kdump-utils RPM with automatic version detection from git tags
#
# On success, return the path of built RPM
#
# Usage:
#   build-rpm.sh [fedora_version]
#
# Examples:
#   build-rpm.sh           # Use auto-detected version, default Fedora version (40)
#   build-rpm.sh 41        # Use auto-detected version, Fedora 41
#

set -e

# Change to repository root
[[ -d ${0%/*} ]] && cd "${0%/*}"/../

# Parse arguments
fedora_version=${1:-40}
dist_abbr=.fc$fedora_version

# Function to detect next version from git tags
get_next_version()
{
	local latest_tag
	local latest_version
	local major minor patch

	# Get the latest tag that matches version pattern (v1.0.x)
	latest_tag=$(git tag --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

	if [[ -z $latest_tag ]]; then
		echo "Warning: No version tags found, using version from spec file" >&2
		rpmspec -q --queryformat "%{VERSION}" kdump-utils.spec
		return
	fi

	# Strip the 'v' prefix
	latest_version=${latest_tag#v}

	# Split version into components
	IFS='.' read -r major minor patch <<< "$latest_version"

	# Increment patch version
	((patch++))

	echo "${major}.${minor}.${patch}"
}

VERSION=$(get_next_version)

# Function to restore spec file on exit
cleanup()
{
	git checkout -- kdump-utils.spec
}

trap cleanup EXIT

sed -i "s/^Version: .*/Version: $VERSION/" kdump-utils.spec

# Create source archive
SRC_ARCHIVE=kdump-utils-$VERSION.tar.gz

if ! git archive --format=tar.gz -o "$SRC_ARCHIVE" --prefix="kdump-utils-$VERSION/" HEAD; then
	echo "Failed to create kdump-utils source archive"
	exit 1
fi

if ! rpmbuild --quiet -ba \
	-D "dist $dist_abbr" \
	-D "_sourcedir $(pwd)" \
	-D "_builddir $(pwd)" \
	-D "_srcrpmdir $(pwd)" \
	-D "_rpmdir $(pwd)" \
	kdump-utils.spec; then
	echo "Failed to build kdump-utils rpm"
	exit 1
fi

# Verify RPM was created
arch=$(uname -m)
rpm_name=$(rpmspec -D "dist $dist_abbr" -q --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' kdump-utils.spec)
rpm_path="$(pwd)/${arch}/${rpm_name}.rpm"

if [[ ! -f $rpm_path ]]; then
	echo "Failed to find built kdump-utils rpm ($rpm_path doesn't exist)"
	exit 1
fi

echo "$rpm_path"
