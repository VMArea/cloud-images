# Contributing

- **Bugs and requests:** open an issue with the image name and date (for example `debian-13-20261103`).
- **New OS or version:** add `os/<distro>/<version>.yaml`, build it with `./build` and run `./test` on the result. Include the test summary in the pull request.
- **Changes to `build` or `test`:** rebuild and test at least one image per package manager you touch.

Keep commits small, with messages like `feat(build): ...` or `fix(test): ...`.
