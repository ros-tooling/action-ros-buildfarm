# Roadmap

Features deferred from the initial implementation. Each section describes why
it matters and what would be needed to add it.

---

## Overlay workspace support (CI action)

**What:** The ros_buildfarm prerelease pipeline has a second phase that builds
packages downstream of yours -- packages that depend on your package -- to
catch public API or behavior breakage before a release. Currently the CI action
skips this and only runs the underlay (your package).

**Why it matters:** Catches regressions in dependent packages that a unit test
of your package alone would miss. The buildfarm uses this as a signal for
whether a release is safe to sync.

**What it would take:**
- Add `overlay_pkgs` input (space-separated package names registered in the
  rosdistro that should be tested against your changes).
- Pass `--pkg <name>` args to `generate_prerelease_script.py`.
- Expose `overlay_test_result` output and include it in the artifact upload.
- The overlay workspace requires all overlay packages to be resolvable from
  the rosdistro, so this only works when `config_url` points to a distro that
  knows those packages.

---

## Multi-repo CI job (separate action wrapping generate_ci_script.py)

**What:** `generate_ci_script.py` runs a CI sweep over a set of repos defined
in a `.repos` file hosted at a URL, with optional package-selection filters.
This is how the official buildfarm runs its nightly jobs over a whole distro.
The current `ci` action uses the prerelease path instead, which is
single-package oriented.

**Why it matters:** Teams with a full custom mini-distro and their own
buildfarm config may want to run the same nightly-style sweep against their
whole `.repos` workspace rather than building from a local checkout.

**What it would take:**
- New `ci-workspace` action (or a mode flag on the existing `ci` action)
  wrapping `generate_ci_script.py`.
- Inputs: `config_url`, `config_name` (maps to a CI build file in the config),
  `ros_distro`, `os_name`, `os_code_name`, `arch`, `package_selection_args`,
  `underlay_dirs`.
- The config must have CI build files (`ci/*.yaml`) that reference a `.repos`
  URL. This is more infrastructure than the prerelease path.
- Outputs: `install_dir` for chaining multiple build steps (already a pattern
  in the upstream ros_buildfarm CI workflow).

---

## ARM / aarch64 support

**What:** Building packages natively on ARM runners, and/or cross-compiling
ARM binaries on amd64 runners.

**Why it matters:** ROS packages commonly target embedded ARM hardware
(Jetson, Pi, custom boards). Validating on ARM before release avoids
surprises.

**What it would take:**
- **Native ARM builds:** GitHub now offers `ubuntu-24.04-arm` runners.
  The action itself has no amd64-specific logic; the main requirement is
  confirming Docker-in-Docker or the Docker socket is available on those
  runners (ros_buildfarm runs builds inside Docker).
- **Cross-compilation:** The ros_buildfarm release pipeline supports this via
  QEMU/binfmt on x86 hosts, controlled by the `arch` input (e.g. `arm64`
  while running on an `amd64` host). This requires the Docker daemon to have
  binfmt_misc configured, which is the case on standard GitHub-hosted runners.
  Testing is needed to confirm the full pipeline works end to end.
- Show `arch: [amd64, arm64]` matrix in the example workflow once confirmed.

---

## Versioned tag internal ref updates

**What:** The `uses: ./setup` reference inside `ci/action.yaml` is the local
form used for self-testing in this repo. External callers need the remote form
`ros-tooling/action-ros-buildfarm/setup@<tag>`. If `@main` is used, callers
pinned to an older tag silently pull `setup` from `main`.

**What it would take:**
- On each release, swap the comments: activate
  `uses: ros-tooling/action-ros-buildfarm/setup@<tag>` and comment out
  `uses: ./setup` in `ci/action.yaml`. Then create the tag.
- Automate with a release workflow that does a find-and-replace before tagging.
- Alternative: inline the setup steps directly into the action to eliminate
  the sub-action dependency entirely.
