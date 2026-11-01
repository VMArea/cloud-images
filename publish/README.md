# Publishing

Tooling for the monthly release. Nothing here uploads unless `--yes` is given.

```
publish/install-tools
publish/record-test output/debian-13-<date>.qcow2 pass
publish/release output --stage stage --prev-dir <older-manifests> [--upload [--yes]]
```

`release` runs, per redistributable image: package diff (`changes`), SBOM and vulnerability scan (`sbom`), a stage tree `stage/<os>/<version>/<date>/`, `sign`, then `status` for `stage/index.html` and `index.json`. With `--upload` it runs `upload` as a dry run; `--yes` makes it real.

- `install-tools` installs syft, grype, cosign and rclone from pinned official releases into `~/.local/bin`, verifying each against the published checksums.
- `sbom` mounts each image read-only with guestmount, writes `<image>.spdx.json` (syft), `<image>.vulns.json` (grype on the SBOM) and `<image>.vulns-summary.json` (counts by severity as `fixable`, grype `--only-fixed`, and `total`, plus the detected distro). Set `FORCE=1` to redo up-to-date images.
- `changes` writes `<image>.changes.txt` by comparing package lists in the manifests with the newest earlier build of the same OS and version, in the output dir or `--prev-dir`.
- `sign` writes `SHA256SUMS` for a release directory and signs it with cosign (`SHA256SUMS.sig` is a bundle). The key pair lives in `~/.cosign/` on the builder (`cosign.key`, `cosign.pub`, `password` mode 0600) and is generated on first use. Only `publish/cosign.pub` is committed.
- Redistribution: only OS names in `allowed-os.txt` are processed. Ubuntu and Windows are never staged or uploaded. `release` refuses an image without a passing `<image>.test.json`.
- `upload` needs `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` and `R2_BUCKET`. Layout: `<os>/<version>/<date>/<files>`, `<os>/<version>/latest.json`, and `index.html` and `index.json` at the root. Retention keeps the newest three dated builds per OS and version. Dry run is the default.
- `status` builds the static page from the stage tree.

## Test results file

`<image>.test.json` next to the image: `{"result": "pass" | "fail", "tested_at": "<UTC ISO time>", "note": "..."}`. `./test` does not write it yet; `record-test` does.

## Verify a download

Install cosign, fetch `cosign.pub` from this repository, download the image and the files you want together with `SHA256SUMS` and `SHA256SUMS.sig` from the same directory, then:

```
publish/verify <download-dir> cosign.pub
```

It checks the signature on `SHA256SUMS`, then checks every downloaded file against it. Equivalent by hand:

```
cosign verify-blob --key cosign.pub --bundle SHA256SUMS.sig --insecure-ignore-tlog SHA256SUMS
sha256sum --ignore-missing -c SHA256SUMS
```
