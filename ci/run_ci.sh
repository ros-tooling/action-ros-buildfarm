#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Polymath Robotics, Inc.
# SPDX-License-Identifier: Apache-2.0
# Run a ros_buildfarm prerelease CI job.
#
# All configuration is via environment variables:
#
#   Required:
#     ROS_DISTRO        ROS distribution name (e.g. rolling, humble)
#     OS_CODE_NAME      Ubuntu code name (e.g. noble, jammy)
#
#   Optional:
#     CONFIG_URL        Buildfarm config index URL
#                       (default: official ROS 2 config)
#     CONFIG_NAME       Config name within the index (default: default)
#     OS_NAME           OS name (default: ubuntu)
#     ARCH              Target architecture (default: amd64)
#     SOURCE_DIR        Package source directory to copy into ws/src.
#                       Set to empty string to skip pre-population.
#                       (default: current directory)
#     UNDERLAY_REPOS    Space-separated rosdistro repo names for underlay
#     CUSTOM_REPOS      Newline-separated name:type:url:branch descriptors
#     ABORT_ON_TEST_FAILURE  Exit non-zero if tests fail (default: false)
#
# Outputs written to GITHUB_OUTPUT if that variable is set:
#     underlay_test_result   exit code of the test suite
#     install_dir            path to the built install space

set -euo pipefail

CONFIG_URL="${CONFIG_URL:-https://raw.githubusercontent.com/ros2/ros_buildfarm_config/ros2/index.yaml}"
CONFIG_NAME="${CONFIG_NAME:-default}"
OS_NAME="${OS_NAME:-ubuntu}"
ARCH="${ARCH:-amd64}"
SOURCE_DIR="${SOURCE_DIR-${PWD}}"   # default to cwd; explicit empty string skips
UNDERLAY_REPOS="${UNDERLAY_REPOS:-}"
CUSTOM_REPOS="${CUSTOM_REPOS:-}"
ABORT_ON_TEST_FAILURE="${ABORT_ON_TEST_FAILURE:-false}"

: "${ROS_DISTRO:?ROS_DISTRO is required}"
: "${OS_CODE_NAME:?OS_CODE_NAME is required}"

WORK_DIR=$(mktemp -d)
echo "Working in ${WORK_DIR}"

# Show plain Docker build output (not the interactive progress display).
export BUILDKIT_PROGRESS=plain

# Pre-populate underlay workspace with local source
if [[ -n "${SOURCE_DIR}" ]]; then
    mkdir -p "${WORK_DIR}/ws/src"
    cp -r "${SOURCE_DIR}/." "${WORK_DIR}/ws/src/"
    echo "Copied source from ${SOURCE_DIR} into ws/src"
fi

# Build custom repo args
CUSTOM_REPO_ARGS=()
while IFS= read -r repo_spec; do
    [[ -z "${repo_spec}" ]] && continue
    CUSTOM_REPO_ARGS+=(--custom-repo "${repo_spec}")
done <<< "${CUSTOM_REPOS}"

# Build underlay repo positional args
UNDERLAY_ARGS=()
if [[ -n "${UNDERLAY_REPOS}" ]]; then
    read -ra UNDERLAY_ARGS <<< "${UNDERLAY_REPOS}"
fi

echo "::group::Generate prerelease script"
pushd "${WORK_DIR}"
generate_prerelease_script.py \
    "${CONFIG_URL}" \
    "${ROS_DISTRO}" \
    "${CONFIG_NAME}" \
    "${OS_NAME}" \
    "${OS_CODE_NAME}" \
    "${ARCH}" \
    "${UNDERLAY_ARGS[@]+"${UNDERLAY_ARGS[@]}"}" \
    "${CUSTOM_REPO_ARGS[@]+"${CUSTOM_REPO_ARGS[@]}"}" \
    --output-dir .
popd
echo "::endgroup::"

echo "::group::Run build and test"
pushd "${WORK_DIR}"
# The prerelease script is intentionally lenient: it exits 0 even when Docker
# steps fail so that test results can still be collected. We use && to chain
# the output write so that a non-zero exit from prerelease.sh propagates as
# a build failure without also falsely reporting a test result of 0.
PRERELEASE_RC=0
(
    set +eu
    # shellcheck source=/dev/null
    . prerelease.sh -y && {
        UNDERLAY_RC=${test_result_RC_underlay:-0}
        if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
            echo "underlay_test_result=${UNDERLAY_RC}" >> "${GITHUB_OUTPUT}"
        fi
        exit "${UNDERLAY_RC}"
    }
) || PRERELEASE_RC=$?
popd
echo "::endgroup::"

# Read test result written by the subshell, fall back to prerelease exit code.
UNDERLAY_RC=${PRERELEASE_RC}
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    FILE_RC=$(grep 'underlay_test_result=' "${GITHUB_OUTPUT}" 2>/dev/null | tail -1 | cut -d= -f2 || true)
    UNDERLAY_RC=${FILE_RC:-${PRERELEASE_RC}}
fi

# Build failure: prerelease.sh itself exited non-zero (Docker failure, etc.)
# This is always fatal regardless of ABORT_ON_TEST_FAILURE.
if [[ "${PRERELEASE_RC}" != "0" ]]; then
    echo "Build failed (prerelease exit code ${PRERELEASE_RC})"
    exit "${PRERELEASE_RC}"
fi

# Build success check: the prerelease script exits 0 even when Docker steps
# fail silently. The test results directory is volume-mounted back to the host
# by the buildfarm; its absence means the build never completed.
if [[ ! -d "${WORK_DIR}/ws/test_results" ]]; then
    echo "Build failed: no test results directory found -- build likely failed inside Docker"
    exit 1
fi

# Collect test results for artifact upload
if [[ -d "${WORK_DIR}/ws/test_results" ]]; then
    RESULTS_DEST="${GITHUB_WORKSPACE:-.}/.ros_buildfarm_test_results"
    mkdir -p "${RESULTS_DEST}"
    cp -r "${WORK_DIR}/ws/test_results/." "${RESULTS_DEST}/"
fi

if [[ "${ABORT_ON_TEST_FAILURE}" == "true" && "${UNDERLAY_RC}" != "0" ]]; then
    echo "Tests failed (exit code ${UNDERLAY_RC})"
    exit "${UNDERLAY_RC}"
fi
