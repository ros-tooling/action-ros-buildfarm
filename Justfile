docker_socket_gid := `stat -c %g /var/run/docker.sock`
act_user_opts := "--user=" + `id -u` + ":" + `id -g` + " --group-add=" + docker_socket_gid

# Run the CI action locally against the fixture package for a given distro.
# Usage: just ci humble
ci distro:
    act -j test-ci --matrix ros_distro:{{distro}} \
        --container-options "{{act_user_opts}}"
