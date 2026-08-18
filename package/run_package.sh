#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Polymath Robotics, Inc.
# SPDX-License-Identifier: Apache-2.0
# Build .deb packages using the ros_buildfarm binary Docker pipeline.
#
# Uses bloom to generate debian/ packaging metadata and dpkg-buildpackage -S
# for the source package, then hands off to the buildfarm binary Docker
# pipeline via run_binarydeb_job.py --skip-download-sourcepkg. The binary
# build runs in the same generated Docker container as the real buildfarm.
#
# All configuration is via environment variables:
#
#   Required:
#     ROS_DISTRO        ROS distribution name (e.g. rolling, humble)
#     OS_CODE_NAME      Ubuntu code name (e.g. noble, jammy)
#
#   Optional:
#     CONFIG_URL        Buildfarm config index URL (default: official ROS 2 config)
#     OS_NAME           OS name (default: ubuntu)
#     ARCH              Target architecture (default: amd64)
#     SOURCE_DIR        Package source directory (default: current directory)
#     SKIP_TESTS        Set to 'true' to pass --skip-tests to the binary build
#
# Outputs written to GITHUB_OUTPUT if that variable is set:
#     deb_dir           path to directory containing generated .deb files

set -euo pipefail

CONFIG_URL="${CONFIG_URL:-https://raw.githubusercontent.com/ros2/ros_buildfarm_config/ros2/index.yaml}"
OS_NAME="${OS_NAME:-ubuntu}"
ARCH="${ARCH:-amd64}"
SOURCE_DIR="${SOURCE_DIR:-${PWD}}"
SKIP_TESTS="${SKIP_TESTS:-false}"

: "${ROS_DISTRO:?ROS_DISTRO is required}"
: "${OS_CODE_NAME:?OS_CODE_NAME is required}"

WORK_DIR=$(mktemp -d)
PACKAGE_DIR="${WORK_DIR}/package_src"
BINARYPKG_DIR="${WORK_DIR}/binarydeb"
DOCKERFILE_CREATE_DIR="${WORK_DIR}/dockerfile_create"
DOCKERFILE_BUILD_DIR="${WORK_DIR}/dockerfile_build"
RBF_DIR="${WORK_DIR}/ros_buildfarm"
KEY_DIR="${WORK_DIR}/keys"

mkdir -p "${BINARYPKG_DIR}" "${DOCKERFILE_CREATE_DIR}" "${DOCKERFILE_BUILD_DIR}" "${KEY_DIR}"
cp -r "${SOURCE_DIR}/." "${PACKAGE_DIR}/"

# ── Setup ─────────────────────────────────────────────────────────────────────
echo "::group::Setup"

# Clone ros_buildfarm source -- Docker containers expect it at /tmp/ros_buildfarm.
# The pip-installed package doesn't preserve the scripts/ source tree layout.
git clone --depth 1 \
    https://github.com/ros-infrastructure/ros_buildfarm.git \
    "${RBF_DIR}"

# Get the ROS apt repository GPG key for the Docker build environment.
# Install ros2-apt-source (which manages the key), then export in ASCII armor.
# The Dockerfile template embeds this key via signed-by= (not apt-key).
ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
    | grep -F "tag_name" | awk -F'"' '{print $4}')
# shellcheck source=/etc/os-release
. /etc/os-release
curl -L -o /tmp/ros2-apt-source.deb \
    "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.${UBUNTU_CODENAME:-${VERSION_CODENAME}}_all.deb"
sudo dpkg -i /tmp/ros2-apt-source.deb
gpg --no-default-keyring \
    --keyring /usr/share/keyrings/ros2-latest-archive-keyring.gpg \
    --armor --export > "${KEY_DIR}/ros.asc"
sudo apt-get update -q

echo "::endgroup::"

# ── Source package generation ─────────────────────────────────────────────────
echo "::group::bloom-generate debian"
cd "${PACKAGE_DIR}"
bloom-generate debian \
    --os-name "${OS_NAME}" \
    --os-version "${OS_CODE_NAME}" \
    --ros-distro "${ROS_DISTRO}"
echo "::endgroup::"

DEB_SOURCE=$(dpkg-parsechangelog --show-field Source)
DEB_VERSION=$(dpkg-parsechangelog --show-field Version)
UPSTREAM_VERSION="${DEB_VERSION%-*}"

# Derive the ROS package name from the Debian source name.
# bloom names sources ros-<distro>-<pkg-with-hyphens>; reverse to get pkg name.
PKG_NAME=$(echo "${DEB_SOURCE}" | sed "s/^ros-${ROS_DISTRO}-//;s/-/_/g")

echo "Debian source:    ${DEB_SOURCE}"
echo "Debian version:   ${DEB_VERSION}"
echo "Upstream version: ${UPSTREAM_VERSION}"
echo "ROS package name: ${PKG_NAME}"

# Create orig tarball -- dpkg-buildpackage -S needs it in the parent directory
UPSTREAM_DIR="${WORK_DIR}/${DEB_SOURCE}-${UPSTREAM_VERSION}"
mkdir -p "${UPSTREAM_DIR}"
rsync -a --exclude='.git' --exclude='debian' "${PACKAGE_DIR}/" "${UPSTREAM_DIR}/"
tar czf "${WORK_DIR}/${DEB_SOURCE}_${UPSTREAM_VERSION}.orig.tar.gz" \
    -C "${WORK_DIR}" "${DEB_SOURCE}-${UPSTREAM_VERSION}"

echo "::group::dpkg-buildpackage -S (source package)"
dpkg-buildpackage -S -us -uc -d
echo "::endgroup::"

# Copy source artifacts to the binarypkg dir that the Docker pipeline will use
find "${WORK_DIR}" -maxdepth 1 \
    \( -name "${DEB_SOURCE}_*.dsc" -o -name "${DEB_SOURCE}_*.tar.*" \) \
    -exec cp {} "${BINARYPKG_DIR}/" \;

# ── Binary build via buildfarm Docker pipeline ────────────────────────────────
# run_binarydeb_job.py generates the Dockerfile for the "create task" container.
# That container (when run) extracts the source and generates the binary build
# Dockerfile via create_binarydeb_task_generator.py. We then build and run that
# second container to produce the .deb. This mirrors the buildfarm binary job
# exactly, with --skip-download-sourcepkg bypassing the apt source fetch.
RBF_ARGS=(
    --rosdistro-index-url "${CONFIG_URL}"
    "${ROS_DISTRO}"
    "${PKG_NAME}"
    "${OS_NAME}"
    "${OS_CODE_NAME}"
    "${ARCH}"
    --distribution-repository-urls "http://packages.ros.org/ros2/${OS_NAME}"
    --distribution-repository-key-files "${KEY_DIR}/ros.asc"
    --binarypkg-dir "${BINARYPKG_DIR}"
    --dockerfile-dir "${DOCKERFILE_CREATE_DIR}"
    --skip-download-sourcepkg
)
if [[ "${SKIP_TESTS}" == "true" ]]; then
    RBF_ARGS+=(--skip-tests)
fi

echo "::group::Generate binary task Dockerfile"
run_binarydeb_job.py "${RBF_ARGS[@]}"
echo "::endgroup::"

IMAGE_TAG="${ROS_DISTRO}_${OS_CODE_NAME}"

echo "::group::Docker build: create-task"
docker build -t "binarydeb_create:${IMAGE_TAG}" "${DOCKERFILE_CREATE_DIR}"
echo "::endgroup::"

echo "::group::Docker run: create-task"
# Runs get_sourcedeb.py --skip-download-sourcepkg (just dpkg-source -x on the .dsc)
# then create_binarydeb_task_generator.py which generates the binary build Dockerfile.
docker run --rm \
    -v "${RBF_DIR}:/tmp/ros_buildfarm:ro" \
    -v "${BINARYPKG_DIR}:/tmp/binarydeb" \
    -v "${DOCKERFILE_BUILD_DIR}:/tmp/docker_build_binarydeb" \
    -e DOCKER_PARENT_PID=$$ \
    "binarydeb_create:${IMAGE_TAG}"
echo "::endgroup::"

echo "::group::Docker build: binary build"
docker build -t "binarydeb_build:${IMAGE_TAG}" "${DOCKERFILE_BUILD_DIR}"
echo "::endgroup::"

echo "::group::Docker run: binary build (produces .deb)"
# Runs build_binarydeb.py which calls apt-src import + dpkg-buildpackage -b.
# The .deb files land in /tmp/binarydeb (= ${BINARYPKG_DIR} on the host).
docker run --rm \
    -v "${RBF_DIR}:/tmp/ros_buildfarm:ro" \
    -v "${BINARYPKG_DIR}:/tmp/binarydeb" \
    -e DOCKER_PARENT_PID=$$ \
    "binarydeb_build:${IMAGE_TAG}"
echo "::endgroup::"

# ── Collect artifacts ─────────────────────────────────────────────────────────
DEB_DIR="${GITHUB_WORKSPACE:-.}/.ros_buildfarm_debs"
mkdir -p "${DEB_DIR}"
find "${BINARYPKG_DIR}" -name '*.deb' -exec cp {} "${DEB_DIR}/" \;

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "deb_dir=${DEB_DIR}" >> "${GITHUB_OUTPUT}"
fi

echo "Generated packages:"
ls -lh "${DEB_DIR}"
