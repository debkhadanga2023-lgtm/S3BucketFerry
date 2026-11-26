# Changelog

## 0.4.2 - 2026-11-26

- **The migration tasks are connected steps.** The task tabs are numbered
  1 Scan, 2 Migrate, 3 Verify, 4 Cutover, 5 Certificate and carry the source and
  target chosen in the form (updated as you change them), so the next step
  opens with the same buckets. Cleanup is set apart and carries nothing.
- **Next step after every finished task and job**: Scan -> Migrate this bucket
  (dry run); dry run -> Run the migration for real; migrate -> Verify, Cutover
  (dry run first), Migrate again; failures or differences -> Migrate again;
  verify -> Cutover, Issue a certificate; cutover dry run -> Run the cutover
  for real; cutover or certificate -> Open the certificate. Each opens the form
  filled in with the same buckets and settings; nothing starts until you select
  its button, and a link never ticks the Mirror deletes confirmation. Task
  forms accept every setting in their address (`?src=...&dst=...&workers=4&
  dry-run=off`).
- **Running now on every page**: the tasks running (from the web interface,
  linking to their page with Stop) and jobs started on the command line
  (marked CLI, linking to their job page), each with its source, target and
  progress; the menu shows their number beside Activity.
- Fixed: the profiles page used an inline style that the page's security
  policy blocked (a browser console error). A test now keeps inline styles
  and scripts out of the templates.
- User guide: section 8 opens with the steps, the next-step table and Running
  now; 8.1, 8.2, 8.4, 8.7 and 8.8 use the new buttons; new and updated
  screenshots. Help page updated to match.
- Tests: next steps for every task and result, settings carried, the deletes
  confirmation never prefilled, numbered tabs, and the Running now bar with a
  web task, its job and a command-line job.

## 0.4.1 - 2026-11-24

- **Bucket lists in the task forms.** Choosing a profile in Scan, Migrate,
  Verify, Cutover, Certificate or Cleanup lists the buckets that profile can
  see, for the source and the target; choosing one fills the bucket box, which
  can still be typed in (for `bucket/prefix`, or a bucket the key may not
  list). The list is read with the current keys file. When it can't be shown,
  the reason appears under the profile in one line with a hint (key not
  allowed to list buckets, wrong keys, untrusted certificate, wrong region
  with the expected one). Without JavaScript the forms work as before.
- **`profile buckets --name NAME [--json]`**: lists a profile's buckets on the
  command line.
- **Scan, then migrate.** A finished scan's task page and job page have
  **Migrate this bucket**, which opens Migrate with the scanned profile and
  bucket as the source. Task forms also accept `?src=profile:bucket` and
  `?dst=` in their address.
- `profile list` shows "none (plain HTTP)" for `http://` endpoints, like the
  web interface.
- Tests: the bucket list endpoint, error summaries (including the region
  hint), form prefill and the Migrate buttons; the integration test lists the
  buckets of an HTTPS profile and checks the certificate hint. A UI test no
  longer races with tasks still running at cleanup.
- User guide: section 8.1 (bucket list, Migrate this bucket, with new
  screenshots), 8.2 steps, `profile buckets` and corrected sample output in
  section 5, two troubleshooting rows. Help page updated to match.

## 0.4.0 - 2026-11-23

**Upgrading:** from 0.3.10, `sudo s3bucketferry upgrade` is enough. From 0.3.9
or earlier, also restart the web interface once (see 0.3.10 below). User
guide, section 13, "Upgrading to 0.4.0".

- **Import the storage's HTTPS certificate into a profile.** For storage with
  a certificate from the customer's own CA: in the web interface, choose the
  PEM file or paste it in the profile form (add or Edit); on the command line,
  `profile add ... --ca-cert-import FILE`. The certificate is checked
  (refused if it holds a private key or isn't PEM) and a copy is kept in the
  state folder (`certs/<profile>.pem`). Its name, issuer, expiry and SHA-256
  fingerprint are shown after the import and on the edit form, which can also
  remove it. The profiles list and `profile list` show the certificate and its
  expiry, and flag an expired one. `--ca-cert FILE` (refer to a file on the
  server) still works and is now checked too. Removing a profile removes its
  imported certificate.
- **Each profile's certificate and bypass apply to its own endpoint only.**
  rclone's global `--ca-cert` replaces the system's trusted CAs for every
  endpoint, and `--no-check-certificate` turns checks off for every endpoint.
  S3BucketFerry now passes them per endpoint (rclone connection-string
  overrides), so the source and target can each have their own customer CA, a
  profile without one keeps trusting the public CAs, and the bypass on one
  profile no longer turns checks off for the other. Tested against two HTTPS
  S3 servers with different private CAs.
- **Bypass ("Do not verify the certificate", `--insecure-tls`)** is explained
  in the form, warned about when saved, and shown as **NOT VERIFIED** in the
  list.
- **Migration certificates record how each endpoint's HTTPS certificate was
  checked** (source and target), with the CA's name and fingerprint; a bypass
  adds a limitation line.
- `profile test` prints how the certificate is checked, and explains common
  TLS errors (unknown authority, expired, wrong name, HTTP endpoint).
- Profiles that use an existing rclone remote now show "as set in the rclone
  remote" in the TLS column (web and `profile list`), instead of "system CAs".
- The web interface accepts file uploads (forms are limited to 4 MB).
- The profile form's key reminder no longer says to restart the web interface
  (not needed since 0.3.10).
- User guide: new "Use an existing rclone remote (advanced)" in section 5
  (what it is, creating the remote as the service user, protecting and
  encrypting rclone.conf with `RCLONE_CONFIG_PASS` in the keys file, what
  doesn't apply) and two troubleshooting rows; Help page to match.
- User guide: new "HTTPS certificates of the storage systems" in section 5,
  updated form screenshots and steps, command-line examples, "Upgrading to
  0.4.0", `certs/` in section 14, six troubleshooting rows, glossary. Help page
  updated to match.
- Tests: PEM parsing, import, summaries and hints; per-profile overrides,
  including Windows paths; web upload, paste, keep on edit, remove, bypass.

## 0.3.10 - 2026-11-23

**Upgrading from 0.3.9 or earlier, once:** after `sudo s3bucketferry upgrade`,
run `sudo systemctl restart s3bucketferry-ui` (the old upgrade script doesn't
restart it), and preferably `sudo s3bucketferry service setup` (press Enter
for each answer) so the service records where the keys file is; it restarts
the service too. User guide,
section 13, "Upgrading to 0.3.10".

- **Changed keys are used without a restart.** The web interface reads the
  keys file again before every task it starts (scan, migrate, verify, cutover,
  certificate, profile test, resume and the rest) and gives the task the
  current values. The first line of each task's output says which keys file was
  read and which variables changed, were added or were removed since the
  previous task; key values are never shown or logged. A task already running
  keeps its keys. The file is found through `S3BF_KEYS_FILE` (now written into
  the service by `service setup`), the service's `EnvironmentFile=`, or
  `~/.config/s3bf-keys.env`. After saving a profile, the "not set" note checks
  the keys file too.
- **`upgrade` always restarts the web interface.** It restarts every
  `s3bucketferry*` service that is running or enabled (or only `--service
  NAME`), and checks each one is running the program just installed. Without
  root it runs itself again with `sudo` (asking for the password) *before*
  changing anything; if it can't get root, it stops with nothing changed. A web
  interface started by hand is reported, since it must be restarted by hand.
  New `--no-restart` changes only the files, with a warning. `--force` during a
  migration now warns that the restart stops the tasks the web interface
  started.
- User guide: sections 4, 5, 6 and 13 and troubleshooting updated (no restart
  after key changes; upgrade restarts and asks for sudo; new messages). Help
  page updated to match.
- Tests: keys file parsing, change detection without values, a task getting
  the current value (portable: also on Windows); service file round trip with `S3BF_KEYS_FILE`; upgrade
  restarts running services only, refuses without root before changing
  anything, and `--no-restart`.

## 0.3.9 - 2026-11-20

- **Edit a connection profile in the web interface.** Users with full access
  have an **Edit** button next to each profile; the form opens filled in with
  the saved settings, with **Cancel**. Previously a profile had to be added
  again from scratch.
- **Keys typed into a key variable field are refused.** The access key and
  secret key fields take the *name* of an environment variable. A value that
  looks like a real key (for example `AKIA...`, a long run of letters and
  digits, or a secret containing `/ + =`) is refused, in the web interface and
  on the command line, without showing the value back. Names starting with
  `RCLONE_` are refused too.
- **Profiles that already hold a key are masked.** The profiles page and
  `profile list` show **(hidden)** instead of the value, with a warning to edit
  the profile; the edit form never sends the key to the browser; profile test
  errors don't print it.
- After saving a profile, the web interface says when a named variable isn't
  set for it yet.
- The profile form's key fields are labelled "Name of the variable ... (not
  the key)", with a reminder box at the top of the form.
- User guide: highlighted warning in section 5, new "Edit or fix a profile"
  subsection with screenshots, three new troubleshooting rows; updated
  screenshots of the profiles page and form. Help page updated to match.
- Tests: key detection, refusal without echo, masking of stored keys, editing.

## 0.3.8 - 2026-11-19

- **Resume in the web interface.** The page of a stopped, failed or partly
  failed migrate job has a **Resume** button; a completed job has **Run
  again** (an incremental pass). It runs `resume` as a task, with the same
  settings as the job.
- **Resume skips finished worker shares.** With several workers, S3BucketFerry
  records which shares of the source finished, the moment each one finishes. A
  resume of a job that stopped or failed part-way doesn't list those shares
  again, which saves a lot of time on very large buckets; prefixes added to the
  source since then are copied by an extra share. `resume <id> --full` (or
  **Check the finished shares again too**) checks everything. A resume of a
  completed job always checks everything. The job summary shows "worker
  shares: N of M finished".
- **Jobs left behind by a crash or restart** are now shown as interrupted
  (Linux and macOS), with a note, so they can be resumed. Previously they kept
  showing "running".
- **Low-memory listing for huge buckets:** `--no-fast-list` (web interface:
  Advanced options > Low-memory listing) lists the buckets prefix by prefix
  instead of all at once, for migrations and their integrity checks.
- The web interface's "Skip the integrity check" option now explains that it
  saves a second full listing on large migrations and that cutover always
  checks everything.
- User guide, section 10: new "Stop and resume" (with a screenshot) and "Very
  large buckets (millions of objects)"; options tables, failed-object retry
  and troubleshooting updated. Help page: new "Stop and resume" part and
  troubleshooting rows.
- Tests: resume after a partial failure skips the finished share and copies a
  newly added prefix; `--full`; `--no-fast-list`; abandoned-job detection; the
  web Resume button. Also tested by killing a migration with `kill -9` and
  resuming it.

## 0.3.7 - 2026-11-19

- **Separate public download repository.** The source code can now be kept in
  a private repository (for example `S3BucketFerry-source`) while releases are
  published to the public `debkhadanga2023-lgtm/S3BucketFerry` repository. It
  keeps the original name, so installed copies keep upgrading from it, and the
  guide's screenshot links, the web interface's online guide link and
  `upgrade.sh` downloads keep working. The Release workflow publishes there
  when the repository variable `PUBLIC_REPO` and the secret
  `PUBLIC_REPO_TOKEN` are set (`scripts/publish-public.sh`); without them it
  works as before. A new "Publish to public repository" workflow copies
  existing releases there once. Steps are in the README ("Repositories and
  releases").
- Release packages contain a README written for users (`public/README.md`),
  which is also the public repository's front page.
- User guide: section 3 explains where the downloads come from; the
  build-from-source part is now for maintainers only (13.8).

## 0.3.6 - 2026-11-19

- **Offline upgrade.** `sudo s3bucketferry upgrade --package FILE` installs a
  release package copied to the machine (USB drive, file share, scp), with no
  internet access: it checks it against `SHA256SUMS.txt` next to it (or
  `--checksums FILE`), checks it is for this machine's system and CPU, keeps
  the current install for `--rollback`, and restarts the service, like the
  online upgrade. `--rclone-zip FILE` does the same for an rclone zip with
  rclone's `SHA256SUMS`. Without a checksum file nothing is changed; `--force`
  reinstalls the same version. From 0.3.5 or earlier, run the `upgrade.sh`
  inside the new package once.
- User guide: offline installation for Linux and Windows (section 3,
  including checking the download with `sha256sum` or PowerShell
  `Get-FileHash`), a new section 13.9 "Offline upgrade" for Linux and Windows
  (Windows is 13.10 and upgrade problems 13.11 now), and troubleshooting rows
  for offline messages. The guide notes that internet access is needed only
  to download the tool, and Git never.
- Help page: notes that the guide covers offline installation.
- Tests: the upgrade test installs a package and an rclone zip with every
  download address pointing nowhere, and checks the missing-checksum, wrong-CPU
  and same-version cases.

## 0.3.5 - 2026-11-19

- **`service setup`: choose HTTP or HTTPS for the web interface service.**
  `sudo s3bucketferry service setup` asks which user runs the service, whether
  browsers connect over HTTPS on port 8443 (default) or plain HTTP on port
  8080, the port, and which certificate HTTPS uses: the generated one (its file
  names are shown: `tls/server.crt`, `tls/server.key`, `tls/ca.crt`, with
  optional extra host names) or your own certificate and key. Your own files
  are checked (key matches, not expired, warns before expiry and when the
  certificate doesn't name the machine) and copied to `tls/own-server.crt` and
  `tls/own-server.key`, owned by the service user. Setup then gives the state
  folder and keys file to the service user, backs up the old service file,
  writes `/etc/systemd/system/s3bucketferry-ui.service`, checks the port is
  free, restarts the service, waits until it answers with the expected
  certificate, prints the addresses and certificate details, and offers to
  open the port in ufw or firewalld. Run it again to change any setting.
  `--yes` with `--user`, `--protocol`, `--port`, `--address`, `--certificate`,
  `--cert`, `--key`, `--tls-hosts`, `--firewall` and `--service` runs it
  without questions. New `service show`.
- **Upgrade:** after upgrading, `upgrade.sh` offers to run `service setup` for
  a service it did not write (with `--yes`, it prints the command). Upgrading
  from 0.3.4 runs 0.3.4's script, so run `sudo s3bucketferry service setup`
  once afterwards to move a service on 8080 to HTTPS on 8443.
- User guide: section 6 rewritten around `service setup`, with a sample run,
  the questions and defaults, the certificate files, commands without
  questions, and using your own certificate; the manual service file is kept
  as an alternative. Install (section 3) points to it, section 13 has
  "Upgrading to 0.3.5", and troubleshooting has rows for setup messages and a
  service still on port 8080.
- Help page: administrators switch between HTTPS and HTTP with `service
  setup`; a troubleshooting row for an old port 8080 address.
- Tests: `scripts/service-test.sh` runs setup against a stand-in systemctl
  that really starts the web interface (0.3.4-style service to HTTPS on 8443,
  HTTP on 8080, own certificate, back to generated, mismatched key, busy
  port); run in CI. The upgrade test covers the setup offer.

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
