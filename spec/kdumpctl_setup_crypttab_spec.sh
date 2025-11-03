#!/bin/bash
Describe "kdumpctl "
	Include ./kdumpctl
	# dinfo is a bit complex for unit tets, simply mock it
	dinfo() {
		echo "$1"
	}
	restorecon() {
		:
	}

	Describe "setup_crypttab()"
		# Set up global variables and mocks for each test
		# shellcheck disable=SC2016 # expand expression later
		BeforeEach 'CRYPTTAB_FILE=$(mktemp)'
		# shellcheck disable=SC2016 # expand expression later
		AfterEach 'rm -f "$CRYPTTAB_FILE"'

		Context "when everything is correct"
			It "adds link-volume-key to specified UUIDs"
				# Arrange
				get_all_kdump_crypt_dev() {
					echo "uuid-001"
					echo "uuid-003"
					echo "uuid-005"
					echo "uuid-006"
					echo "uuid-007"
				}
				cat >"$CRYPTTAB_FILE" <<EOF
luks-001 UUID=uuid-001 none discard
luks-002 UUID=uuid-002 none discard
# only two mandatory fields
luks-003 UUID=uuid-003
# two mandatory fields + one optional field
luks-005 UUID=uuid-005 -
# tab as delimiter
luks-006	UUID=uuid-006
luks-007 UUID=uuid-007 none discard,link-volume-key=TO_RE_REPLACED
EOF
				When call setup_crypttab
				The status should be success
				The output should include "Success! $CRYPTTAB_FILE has been updated."
				The output should include "to run 'dracut -f --regenerate-all'"
				The file "$CRYPTTAB_FILE" should be file
				The contents of file "$CRYPTTAB_FILE" should eq \
					"luks-001 UUID=uuid-001 none discard,link-volume-key=@u::%logon:${LUKS_KEY_PRFIX}uuid-001
luks-002 UUID=uuid-002 none discard
# only two mandatory fields
luks-003 UUID=uuid-003 none link-volume-key=@u::%logon:${LUKS_KEY_PRFIX}uuid-003
# two mandatory fields + one optional field
luks-005 UUID=uuid-005 - link-volume-key=@u::%logon:${LUKS_KEY_PRFIX}uuid-005
# tab as delimiter
luks-006 UUID=uuid-006 none link-volume-key=@u::%logon:${LUKS_KEY_PRFIX}uuid-006
luks-007 UUID=uuid-007 none discard,link-volume-key=@u::%logon:${LUKS_KEY_PRFIX}uuid-007"
			End
		End

		Context "with safety checks and edge cases"

			It "succeeds if no LUKS device used for kdump"
				get_all_kdump_crypt_dev() { return 0; }
				echo "luks-001 UUID=uuid-001" >"$CRYPTTAB_FILE"
				When call setup_crypttab
				The status should be success
				The output should include "No LUKS-encrypted device found to process. Exiting."
			End

			It "aborts if target UUID is not in crypttab"
				get_all_kdump_crypt_dev() { echo "uuid-nonexistent"; }
				echo "luks-001 UUID=uuid-001" >"$CRYPTTAB_FILE"
				When call setup_crypttab
				The status should be failure
				The stderr should include "Device UUID=$(get_all_kdump_crypt_dev) doesn't exist"
			End

			It "aborts if target UUID is only in a commented-out line"
				get_all_kdump_crypt_dev() { echo "uuid-001"; }
				echo "#luks-001 UUID=uuid-001" >"$CRYPTTAB_FILE"
				When call setup_crypttab
				The status should be failure
				The stderr should include "Device UUID=$(get_all_kdump_crypt_dev) doesn't exist"
			End

			It "succeeds with no changes if crypttab is already correct"
				get_all_kdump_crypt_dev() { echo "uuid-001"; }
				echo "luks-001 UUID=uuid-001 none link-volume-key=@u::%logon:${LUKS_KEY_PRFIX}uuid-001" >"$CRYPTTAB_FILE"
				When call setup_crypttab
				The status should be success
				The output should include "No changes were needed."
			End
		End

	End

	Describe "remove_luks_vol_keys()"

		Context "when LUKS keys exist in keyring"
			It "removes all LUKS keys with correct prefix"
				# Arrange - mock keyctl to return keys with LUKS prefix
				keyctl() {
					case "$1" in
					"list")
						if [[ "$2" == "@u" ]]; then
							cat <<EOF
3 keys in keyring:
464821568: --alsw-v     0     0 logon: ${LUKS_KEY_PRFIX}uuid-001
930415407: --alsw-v     0     0 logon: ${LUKS_KEY_PRFIX}uuid-002
123456789: --alsw-v     0     0 logon: other-key-prefix:uuid-003
EOF
							return 0
						fi
						;;
					"unlink")
						echo "keyctl unlink $2" >&2
						return 0
						;;
					*)
						return 1
						;;
					esac
				}

				When call remove_luks_vol_keys
				The status should be success
				The stderr should include "keyctl unlink 464821568"
				The stderr should include "keyctl unlink 930415407"
				The stderr should not include "keyctl unlink 123456789"
			End

		End

		Context "when no LUKS keys exist"
			It "completes successfully with no matching keys"
				# Arrange - return keys but none with LUKS prefix
				keyctl() {
					case "$1" in
					"list")
						if [[ "$2" == "@u" ]]; then
							cat <<EOF
2 keys in keyring:
123456789: --alsw-v     0     0 logon: other-key-prefix:uuid-003
987654321: --alsw-v     0     0 user: regular-user-key
EOF
							return 0
						fi
						;;
					*)
						return 1
						;;
					esac
				}

				When call remove_luks_vol_keys
				The status should be failure
			End

			It "completes successfully when keyring is empty"
				# Arrange
				keyctl() {
					case "$1" in
					"list")
						if [[ "$2" == "@u" ]]; then
							echo "keyring is empty"
							return 0
						fi
						;;
					*)
						return 1
						;;
					esac
				}

				When call remove_luks_vol_keys
				The status should be failure
			End
		End
	End
End
