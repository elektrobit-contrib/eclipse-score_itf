# *******************************************************************************
# Copyright (c) 2026 Contributors to the Eclipse Foundation
#
# See the NOTICE file(s) distributed with this work for additional
# information regarding copyright ownership.
#
# This program and the accompanying materials are made available under the
# terms of the Apache License Version 2.0 which is available at
# https://www.apache.org/licenses/LICENSE-2.0
#
# SPDX-License-Identifier: Apache-2.0
# *******************************************************************************

"""Rule for adding archive content to a QEMU disk image overlay."""

def _copy_files_onto_image_impl(ctx):
    overlay_image = ctx.outputs.out

    args = ctx.actions.args()
    args.add(ctx.file.image.path)
    args.add(overlay_image.path)
    args.add_all([src.path for src in ctx.files.srcs])

    ctx.actions.run_shell(
        inputs = [ctx.file.image] + ctx.files.srcs,
        outputs = [overlay_image],
        arguments = [args],
        execution_requirements = {
            "no-sandbox": "1",
        },
        command = """
set -euo pipefail

BASE_IMAGE="$1"
OVERLAY_IMAGE="$2"
shift 2

BASE_IMAGE_ABS="$(readlink -f "${BASE_IMAGE}")"

BASE_FORMAT="$(qemu-img info --output=json "${BASE_IMAGE_ABS}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["format"])')"

rm -f "${OVERLAY_IMAGE}"
qemu-img create -f qcow2 -b "${BASE_IMAGE_ABS}" -F "${BASE_FORMAT}" "${OVERLAY_IMAGE}" >/dev/null

for src in "$@"; do
    case "${src}" in
        *.tar)
            guestfish --rw -a "${OVERLAY_IMAGE}" -m /dev/sda1:/ tar-in "${src}" /
            ;;
        *.tar.gz|*.tgz)
            guestfish --rw -a "${OVERLAY_IMAGE}" -m /dev/sda1:/ tar-in "${src}" / compress:gzip
            ;;
        *.tar.bz2|*.tbz2)
            guestfish --rw -a "${OVERLAY_IMAGE}" -m /dev/sda1:/ tar-in "${src}" / compress:bzip2
            ;;
        *.tar.xz|*.txz)
            guestfish --rw -a "${OVERLAY_IMAGE}" -m /dev/sda1:/ tar-in "${src}" / compress:xz
            ;;
        *)
            echo "Error: unsupported archive type: ${src}" >&2
            exit 1
            ;;
    esac
done
""",
        mnemonic = "CopyFilesOntoImage",
        progress_message = "Creating image overlay %s" % overlay_image.short_path,
    )

    return [
        DefaultInfo(
            files = depset([overlay_image]),
            runfiles = ctx.runfiles(files = [overlay_image]),
        ),
    ]

_copy_files_onto_image = rule(
    implementation = _copy_files_onto_image_impl,
    attrs = {
        "image": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "srcs": attr.label_list(
            allow_files = [
                ".tar",
                ".tar.gz",
                ".tgz",
                ".tar.bz2",
                ".tbz2",
                ".tar.xz",
                ".txz",
            ],
            default = [],
        ),
        "out": attr.output(
            mandatory = True,
        ),
    },
)

def copy_files_onto_image(name, image, srcs = [], out = None, **kwargs):
    if out == None:
        out = "%s.qcow2" % name

    _copy_files_onto_image(
        name = name,
        image = image,
        srcs = srcs,
        out = out,
        **kwargs
    )
