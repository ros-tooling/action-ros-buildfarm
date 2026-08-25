docker_socket_gid := `stat -c %g /var/run/docker.sock`

# CI action: --user avoids the buildfarm's uid==0 assertion in prerelease.sh.
# /tmp shared so Docker volume mounts resolve on the host (not the act container).
# --group-add grants Docker socket access to the non-root user.
ci_act_opts := "--user=" + `id -u` + ":" + `id -g` \
    + " --group-add=" + docker_socket_gid \
    + " -v /tmp:/tmp"

# Package action: runs as root in act (uid 1000 lacks passwordless sudo in the
# catthehacker image). The script handles the uid==0 restriction internally
# by su-ing to a build user for the ros_buildfarm calls that assert uid != 0.
package_act_opts := "--group-add=" + docker_socket_gid \
    + " -v /tmp:/tmp"

# Run the CI action locally against the fixture package for a given distro.
# Usage: just ci humble
ci distro:
    act --rm -j test-ci --matrix ros_distro:{{distro}} \
        --container-options "{{ci_act_opts}}"

# Run the package action locally against the fixture package for a given distro.
# Usage: just package humble
package distro:
    act --rm -j test-package --matrix ros_distro:{{distro}} \
        --container-options "{{package_act_opts}}"
