#!/usr/bin/env bash
# Loaded by bcachefs-test-libs.sh. Optional strict checks for pinned VM runs.
if [[ ${ktest_expected_profile:-} = kasan ]]; then
    require-kernel-append kasan.fault=panic
fi

init_verify_bcachefs_build()
{
    [[ -n ${ktest_expected_bcachefs_sha:-} ]] || return 0
    local out=${ktest_out:-/ktest-out}/provenance
    local src=$ktest_deps_dir/bcachefs-tools
    local ko config tools_version test_root
    mkdir -p "$out"
    ko=$(modinfo -n bcachefs)
    config=/lib/modules/$(uname -r)/build/.config
    test_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
    [[ $(git -C "$src" rev-parse HEAD) = "$ktest_expected_bcachefs_sha" ]]
    git -C "$src" diff --quiet HEAD
    [[ $(git -C "$test_root" rev-parse HEAD) = "$ktest_expected_test_sha" ]]
    git -C "$test_root" diff --quiet HEAD
    [[ $(cat /sys/module/bcachefs/srcversion) = "$(modinfo -F srcversion "$ko")" ]]
    [[ $(cat /sys/module/bcachefs/version) = "$(modinfo -F version "$ko")" ]]
    [[ $(sha256sum "$config" | cut -d' ' -f1) = "$ktest_expected_config_sha" ]]
    tools_version=$(bcachefs version)
    # bcachefs version uses git describe; require the source's abbreviated SHA.
    [[ $tools_version = *"${ktest_expected_bcachefs_sha:0:12}"* ]]
    case $ktest_expected_profile in
        kasan)
            grep -qx CONFIG_KASAN=y "$config"
            nm -u "$ko" > "$out/module-undefined-symbols.txt"
            grep -q '__asan_' "$out/module-undefined-symbols.txt"
            [[ $(cat /proc/cmdline) = *kasan.fault=panic* ]]
            ;;
        lockdep)
            grep -qx CONFIG_PROVE_LOCKING=y "$config"
            [[ -r /proc/lockdep_stats ]]
            ;;
        plain) ;;
        *) return 1 ;;
    esac
    {
        uname -a
        cat /proc/cmdline
        printf 'bcachefs=%s\ntests=%s\nprofile=%s\n' \
            "$ktest_expected_bcachefs_sha" "$ktest_expected_test_sha" "$ktest_expected_profile"
        printf '%s\n' "$tools_version"
        modinfo "$ko"
        sha256sum "$ko" "$(command -v bcachefs)" "$config"
    } > "$out/guest-manifest.txt"
    cp "$config" "$out/kernel.config"
    echo verified > "$out/verified"
}
