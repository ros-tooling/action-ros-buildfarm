# action-ros-buildfarm

GitHub Actions for building and testing ROS packages using the exact same pipeline as the [ROS buildfarm](https://github.com/ros-infrastructure/ros_buildfarm).

Designed for these use cases:

- Validate that builds will succeed when packages are released into a ROS distribution
- Enable native packaging for creation of custom/private distributions outside the centralized ROS system

## Actions

| Action | Purpose |
|--------|---------|
| [`setup`](#setup-action) | Install `ros_buildfarm` |
| [`ci`](#ci-action) | Build and test using the prerelease pipeline (no rosdistro needed) |

---

## Setup action

Installs `ros_buildfarm` and its dependencies.
Mainly used automatically by the other actions as an initial step.
Use directly if you need to run buildfarm scripts yourself.

```yaml
- uses: ros-tooling/action-ros-buildfarm/setup@main
```

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `ros_buildfarm_ref` | no | | Git ref to install from GitHub instead of PyPI |

---

## CI action

Runs your ROS packages through the same Docker + rosdep + colcon pipeline the buildfarm uses.
Because it uses the `prerelease` job approach, your package **does not** need to be registered in any rosdistro.

```yaml
- uses: ros-tooling/action-ros-buildfarm/ci@main
  with:
    ros_distro: rolling
    os_code_name: noble
```

By default, the contents of `github.workspace` are copied into the build workspace and built.
You can also specify additional repos via `custom_repos` or `underlay_repos`.

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `ros_distro` | yes | | ROS distribution (e.g. `rolling`, `humble`) |
| `os_code_name` | yes | | OS version (e.g. `noble`, `jammy`) |
| `config_url` | no | official ROS 2 config | Buildfarm config index URL |
| `config_name` | no | `default` | Config name within the index |
| `os_name` | no | `ubuntu` | OS name |
| `arch` | no | `amd64` | Target architecture |
| `source_dir` | no | `github.workspace` | Directory of package source to build. Set to `''` to skip. |
| `underlay_repos` | no | | Space-separated repo names from rosdistro to include |
| `custom_repos` | no | | Newline-separated `name:type:url:branch` for repos not in rosdistro |
| `abort_on_test_failure` | no | `false` | Fail the job if tests fail |
| `upload_test_results` | no | `true` | Upload JUnit XML results as an artifact |

### Outputs

| Output | Description |
|--------|-------------|
| `underlay_test_result` | Exit code of the test suite |
| `install_dir` | Path to the built install space (use as underlay for downstream) |

### Using a custom mini-distro config

If you maintain your own rosdistro and buildfarm config, set `config_url` to
your own index:

```yaml
- uses: ros-tooling/action-ros-buildfarm/ci@main
  with:
    config_url: https://raw.githubusercontent.com/myorg/my_buildfarm_config/main/index.yaml
    ros_distro: my_distro
    os_code_name: noble
```

---

## Developing

Formatting and linting standards are maintained via `pre-commit` hooks, configured in [.pre-commit-config.yaml](./.pre-commit-config.yaml).

To have them run locally on commit, install once in the local checkout:

```shell
pre-commit install
```
