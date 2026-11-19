# Changelog

## 0.3.4 - 2026-11-19

- **HTTPS by default for the web interface.** On a network address it now
  serves HTTPS. Each install creates its own certificate authority and server
  certificate on first start (ECDSA P-384, never shipped in the package); the
  server certificate covers the host name, IP addresses and `localhost`, and
  renews itself 30 days before expiry or when the names change. TLS 1.2 and 1.3
  only, with forward-secret AEAD ciphers. The recommended address is
  `--listen 0.0.0.0:8443` (HTTPS), next to 8080 for local HTTP; ports below
  1024 such as 443 also work with `AmbientCapabilities=CAP_NET_BIND_SERVICE`.
  New options `--tls auto|on|off`
  and `--tls-hosts`; `--tls-cert`/`--tls-key` still use your own certificate,
  which also turns on HSTS. New command `tls show|renew`. A clear message
  explains how to allow ports below 1024. **Change:** a service listening on
  `0.0.0.0:8080` now answers on `https://`; add `--tls off` to keep plain HTTP
  (not recommended).
- Help page: a new "Secure connection (HTTPS)" part and troubleshooting rows
  for browser certificate warnings.
- User guide, section 6: HTTPS, the service on port 8443, removing the browser warning
  by trusting the CA on Windows, macOS, Linux and Firefox, certificate
  maintenance, and using your own certificate.

- Fixed: without write access, the upgrade suggested running `upgrade.sh`
  directly, which fails when the file has no execute permission. It now
  suggests `sudo s3bucketferry upgrade` with your options (or `sudo bash
  upgrade.sh ...` when the script was run on its own).
- Code quality: every ignored error is now explicit or handled (`report --out`
  now reports a failed write when closing the file), shell scripts pass
  shellcheck, and the guide builder passes ruff. CI has a new lint job:
  golangci-lint (errcheck, govet, ineffassign, staticcheck, unused, gofmt),
  shellcheck and ruff. Configuration in `.golangci.yml`.
- Text written to files (the certificate's `.txt` and text reports) now goes
  through a writer that keeps the first write error, so a failed write (for
  example a full disk) makes the command fail instead of leaving a cut-off file.

## 0.3.3 - 2026-11-19

- **User guide in the web interface.** A new **User guide** link under Support,
  and a box at the top of the Help page, open the full guide with all its
  screenshots in a new tab. It is served from the `USER_GUIDE.html` that every
  release package installs next to the program, so it works offline; without
  that file, the page links to the guide on GitHub. The Help page stays as the
  short reference.
- **Upgrade and rollback documented step by step** in the User guide (section
  13): checking for a new version and reading `--check`, before upgrading, the
  upgrade itself with sample output, checking the result, rollback and what it
  restores, other options, upgrading from 0.3.1, builds from source, Windows,
  and an upgrade problems table. Upgrade and rollback stay command-line only.

## 0.3.2 - 2026-11-18

- **Dry-run plan.** A dry run now lists every object a real run would copy or
  delete, with sizes and totals: on screen (first 100), on the web UI job page
  (first 500), and in full in `reports/<job>-dry-run-plan.csv`. It is still
  rclone's own `--dry-run`, so it shows exactly what `rclone copy --dry-run`
  or `rclone sync --dry-run` would do. The CSV report includes the plan too.
- **`cutover --dry-run`.** Previews the final sync (with `--mirror-deletes`,
  also the deletes), changes nothing and issues no certificate. The web UI
  Cutover page has a Dry run box, ticked by default.
- The web UI no longer asks for the mirror-deletes confirmation on a dry run,
  because a dry run deletes nothing.
- **Upgrades.** `upgrade.sh` ships in every Linux and macOS package, and
  `s3bucketferry upgrade` runs it: it checks for and installs the newest
  S3BucketFerry and the newest rclone, verifies every download's SHA-256
  checksum, keeps the previous install for `--rollback`, refuses to run while
  a migration is active, and restarts the web UI service. `--check` only
  reports versions. `doctor` points to it.
- **Live progress.** While a migration runs, the screen shows percent done
  (objects and data), objects copied, failed, pending and checked, throughput
  now and on average, elapsed time and ETA, and one line per worker with its
  state, counts, speed and the objects in flight. On a terminal the block is
  redrawn in place; in the web interface and logs it is printed every 10
  seconds. The same status is written to `jobs/<id>.status.json`, and the web
  UI shows it as a live panel with progress bars on the task and job pages.
- **Failed objects listed by name.** Objects that still fail after rclone's
  retries are written to `logs/<job>.failed-objects.tsv` (object and last
  error), shown at the end of the run (first 20), listed on the web UI job page
  (first 500, with a download), counted in `jobs`, and included in the CSV
  report. An object that fails and then succeeds on a retry is not listed.
- **Compressed job files for large jobs.** When a job covers more than 10,000
  objects, its rclone logs, check report, dry-run plan, failed-object list and
  certificate manifests are stored gzip-compressed (`.gz`). Certificate
  evidence is compressed before its checksums are taken, so `sha256sum -c`
  still matches. Change the threshold with `--compress-above N` (0 = always,
  -1 = never), the `S3BF_COMPRESS_ABOVE` variable, or the web UI's advanced
  options. Bucket data is never compressed.
- **Job bundle.** `s3bucketferry job bundle <id>` and the web UI's "All files
  (.tar.gz)" button pack a job's reports (HTML, text, CSV), logs, check
  report, plan, failed-object list and certificate files into one archive.
- rclone statistics are now read every 2 seconds (was 5).
- Fixed a duplicated line in the output of `resume`.
- **User guide rewritten** (`docs/USER_GUIDE.md`) with 25 screenshots from real
  migrations: installation, access keys, generic source and target profiles
  for any S3-compatible storage, step-by-step migration in the web interface
  and on the command line, progress and failures, users, notifications,
  upgrades, troubleshooting and a glossary.
- **Release packages include the guide with its screenshots:**
  `USER_GUIDE.html` is one self-contained page that works offline;
  `USER_GUIDE.md` links its screenshots to the release's files on GitHub.
  Built by `scripts/build-guide.py`.
- `upgrade.sh` can now install packages that contain folders.

## 0.3.1 - 2026-11-18

First published release. (v0.3.0 was tagged, but its release build failed:
the workflow stored the rclone version in an `RCLONE_VERSION` variable, which
rclone reads as its own `--version` option. Build variables are now named
`S3BF_RCLONE_*`.)


- Web interface (`s3bucketferry ui`): login page with logo, dashboard, a page for
  each migration task, activity with live output and a stop button, jobs and
  reports, certificates, connection profiles, notifications, help.
- User management with three access levels (read-only, read-write, full). The
  first user is `s3admin` with the default password from the User Guide, which
  must be changed at first login.
- `user` command to list users, reset a password or unlock an account on the server.
- Audit log records web logins, failed logins, user and profile changes and
  tasks, attributed to the web user.
- User Guide (`docs/USER_GUIDE.md`).
- Requires Go 1.24 to build.

- Release packages now bundle the latest rclone release, downloaded from
  github.com/rclone/rclone at build time and checked against rclone's
  SHA-256 sums, with rclone's MIT license included.
- `scripts/fetch-rclone.sh` and `make rclone` download rclone for local use.
- End-to-end integration test against real rclone (`scripts/integration-test.sh`),
  run in CI and before every release.

## 0.2.0 - 2026-11-12

Renamed to **S3BucketFerry** (binary `s3bucketferry`; environment variables
`S3BF_HOME` and `S3BF_RCLONE`).

Added
- Built-in integrity check after every `migrate` (`--no-verify` to skip).
- `cutover` command: final sync, full verification and migration certificate.
- `certificate` command and migration certificate (HTML, text, JSON, SHA-256
  file) with per-object checksum comparison and bucket manifest digests.
- `cleanup` command for abandoned multipart uploads.
- `migrate` options: `--chunk-size`, `--upload-concurrency`, `--metadata`,
  `--object-lock`, `--acl`, `--workers`, `--quiet-log`; `--bwlimit` timetables.
- Per-profile CA certificate (`profile add --ca-cert`).
- Webhook and e-mail notifications (`notify`).
- `audit.log`, JSON report format, operator/host/version details in every job,
  rclone command lines recorded per job.

Changed
- Every copied object is now logged by default.
- Job records store one log file per worker.

- Published at https://github.com/debkhadanga2023-lgtm/S3BucketFerry with CI and a release workflow
  that attaches binaries for Linux, Windows and macOS to every `v*` tag.

Not yet tested against real rclone or real S3 systems.

## 0.1.0 - 2026-11-11

First version, under the working name `s3bm`: profiles, scan, migrate, verify,
jobs, resume, report.
