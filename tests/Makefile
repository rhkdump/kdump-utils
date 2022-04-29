TEST_CASE ?=
BASE_IMAGE ?=

TEST_ROOT := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
BUILD_ROOT := $(TEST_ROOT)/build
REPO = $(shell realpath $(TEST_ROOT)/../)
ARCH ?= $(shell arch)
SPEC = kexec-tools.spec

DIST ?= fedora
DIST_ABR ?= f
DIST_ABRL ?= fc
DIST_UNSET ?= rhel
RELEASE ?= 33

DEFAULT_BASE_IMAGE_VER ?= 1.2
DEFAULT_BASE_IMAGE ?= Fedora-Cloud-Base-$(RELEASE)-$(DEFAULT_BASE_IMAGE_VER).$(ARCH).raw.xz
DEFAULT_BASE_IMAGE_URL ?= https://dl.fedoraproject.org/pub/fedora/linux/releases/$(RELEASE)/Cloud/$(ARCH)/images/$(DEFAULT_BASE_IMAGE)

BUILD_ROOT = $(TEST_ROOT)/build
RPMDEFINE = --define '_sourcedir $(REPO)'\
	    --define '_specdir $(REPO)'\
	    --define '_builddir $(BUILD_ROOT)'\
	    --define '_srcrpmdir $(BUILD_ROOT)'\
	    --define '_rpmdir $(BUILD_ROOT)'\
	    --define 'dist %{?distprefix}.$(DIST_ABRL)$(RELEASE)'\
	    --define '$(DIST) $(RELEASE)'\
	    --eval '%undefine $(DIST_UNSET)'\
	    --define '$(DIST_ABRL)$(RELEASE) 1'\

KEXEC_TOOLS_SRC = $(filter-out $(REPO)/tests,$(wildcard $(REPO)/*))
KEXEC_TOOLS_TEST_SRC = $(wildcard $(REPO)/tests/scripts/**/*)
KEXEC_TOOLS_NVR = $(shell rpm $(RPMDEFINE) -q --specfile $(REPO)/$(SPEC) 2>/dev/null | grep -m 1 .)
KEXEC_TOOLS_RPM = $(BUILD_ROOT)/$(ARCH)/$(KEXEC_TOOLS_NVR).rpm

all: $(TEST_ROOT)/output/test-base-image

# Use either:
# fedpkg --release $(DIST_ABR)$(RELEASE) --path ../../ local
# or
# rpmbuild $(RPMDEFINE) -ba $(REPO)/$(SPEC)
# to rebuild the rpm, currently use rpmbuild to have better control over the rpm building process
#
$(KEXEC_TOOLS_RPM): $(KEXEC_TOOLS_SRC)
	sh -c "cd .. && fedpkg --release f$(RELEASE) sources"
	@echo Rebuilding RPM due to modification of sources: $?
	rpmbuild $(RPMDEFINE) -ba $(REPO)/$(SPEC)

$(BUILD_ROOT)/base-image:
	mkdir -p $(BUILD_ROOT)
ifeq ($(strip $(BASE_IMAGE)),)
	wget $(DEFAULT_BASE_IMAGE_URL) -O $(BUILD_ROOT)/$(DEFAULT_BASE_IMAGE)
	$(TEST_ROOT)/scripts/build-image.sh \
		$(BUILD_ROOT)/$(DEFAULT_BASE_IMAGE)\
		$(BUILD_ROOT)/base-image
else
	$(TEST_ROOT)/scripts/build-image.sh \
		$(BASE_IMAGE)\
		$(BUILD_ROOT)/base-image
endif

$(BUILD_ROOT)/inst-base-image: $(BUILD_ROOT)/base-image
	@echo "Building installation base image"
	echo $(KEXEC_TOOLS_NVR)
	$(TEST_ROOT)/scripts/build-image.sh \
		$(BUILD_ROOT)/base-image \
		$(BUILD_ROOT)/inst-base-image \
		$(TEST_ROOT)/scripts/build-scripts/base-image.sh

$(TEST_ROOT)/output/test-base-image: $(BUILD_ROOT)/inst-base-image $(KEXEC_TOOLS_RPM) $(KEXEC_TOOLS_TEST_SRC) $(EXTRA_RPMS)
	@echo "Building test base image"
	mkdir -p $(TEST_ROOT)/output
	$(TEST_ROOT)/scripts/build-image.sh \
		$(BUILD_ROOT)/inst-base-image \
		$(TEST_ROOT)/output/test-base-image \
		$(TEST_ROOT)/scripts/build-scripts/test-base-image.sh \
		$(KEXEC_TOOLS_RPM) $(EXTRA_RPMS)

test-run: $(TEST_ROOT)/output/test-base-image
ifeq ($(strip $(TEST_CASE)),)
	$(TEST_ROOT)/scripts/run-test.sh
else
	$(TEST_ROOT)/scripts/run-test.sh --console $(TEST_CASE)
endif

clean:
	rm -rf $(TEST_ROOT)/build
	rm -rf $(TEST_ROOT)/output
