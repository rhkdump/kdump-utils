#!/bin/bash

check() {
    return 255
}

depends() {
    return 0
}

install() {
    # shellcheck disable=SC2154
    mv -f "$initdir/init" "$initdir/init.dracut"
    # shellcheck disable=SC2154
    inst_script "$moddir/init-fadump.sh" /init
    chmod a+x "$initdir/init"

    # Install required binaries for the init script (init-fadump.sh)
    inst_multiple sh modprobe grep mkdir mount
    if dracut_module_included "squash"; then
        inst_multiple cp pivot_root umount
    else
        inst_multiple ls mv switch_root
    fi
}
