# action-ros-buildfarm

Actions to run [ros_buildfarm](https://github.com/ros-infrastructure/ros_buildfarm) scripts in GitHub workflows.

The goal of this repository is to mimic those jobs as closely as possible in user-run workflows, for these benefits:

- Build confidence that builds will succeed when packages are released into a ROS distribution
- Enable native packaging for creation of custom/private distributions

## Developing

Formatting and linting standards are maintained via `pre-commit` hooks, configured in [.pre-commit-config.yaml](./.pre-commit-config.yaml).

To have them run locally on commit, install once in the local checkout:

```shell
pre-commit install
```
