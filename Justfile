docker_socket_gid := `stat -c %g /var/run/docker.sock`

# act runs the job inside a container. The ros_buildfarm generates temp dirs
# under /tmp/ and spawns sibling Docker containers (via the host socket) with
# volume mounts to those paths. The host daemon resolves those paths on the
# HOST, not inside the act container -- so /tmp must be shared to make them
# match. --user avoids the buildfarm's uid==0 assertion. --group-add grants
# Docker socket access to the non-root user.
act_container_opts := "--user=" + `id -u` + ":" + `id -g` \
    + " --group-add=" + docker_socket_gid \
    + " -v /tmp:/tmp"

# Run the CI action locally against the fixture package for a given distro.
# Usage: just ci humble
ci distro:
    act -j test-ci --matrix ros_distro:{{distro}} \
        --container-options "{{act_container_opts}}"
