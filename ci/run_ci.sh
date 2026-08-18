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
# Run in a subshell so test failures don't abort the outer script.
# Write outputs from inside the subshell since the vars live there.
# -y accepts workspace content already present (our pre-populated ws/src).
(
    set +eu
    # shellcheck source=/dev/null
    . prerelease.sh -y
    UNDERLAY_RC=${test_result_RC_underlay:-$?}
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "underlay_test_result=${UNDERLAY_RC}" >> "${GITHUB_OUTPUT}"
    fi
    exit "${UNDERLAY_RC}"
) || true
popd
echo "::endgroup::"

UNDERLAY_RC=0
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    UNDERLAY_RC=$(grep 'underlay_test_result=' "${GITHUB_OUTPUT}" | tail -1 | cut -d= -f2 || echo 0)
fi

# Capture install dir for downstream steps
INSTALL_DIR=$(find "${WORK_DIR}" -maxdepth 5 -type d -name 'install' 2>/dev/null | head -1 || true)
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "install_dir=${INSTALL_DIR}" >> "${GITHUB_OUTPUT}"
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
