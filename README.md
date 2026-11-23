# S3BucketFerry

[![Release](https://img.shields.io/github/v/release/debkhadanga2023-lgtm/S3BucketFerry?include_prereleases)](https://github.com/debkhadanga2023-lgtm/S3BucketFerry/releases)

**Copy, verify and certify S3 bucket migrations between any S3-compatible
storage systems, from the browser or the command line.**

S3BucketFerry migrates buckets from one S3-compatible storage system to
another: on-premises object storage, public clouds and software S3 gateways.
[rclone](https://rclone.org) moves the data; S3BucketFerry adds a guided flow,
verification, live progress, job history, reports and a migration certificate.

    connect -> scan -> dry run -> migrate + verify -> cutover -> certificate

This repository holds the **release packages** and the **User Guide**.

## Download

Get the package for your system from the
[Releases page](https://github.com/debkhadanga2023-lgtm/S3BucketFerry/releases),
together with `SHA256SUMS.txt` to check the download:

| System | Package |
|---|---|
| Linux, Intel/AMD | `s3bucketferry-<version>-linux-amd64.tar.gz` |
| Linux, ARM | `s3bucketferry-<version>-linux-arm64.tar.gz` |
| Windows | `s3bucketferry-<version>-windows-amd64.zip` |
| macOS, Intel | `s3bucketferry-<version>-macos-amd64.tar.gz` |
| macOS, Apple silicon | `s3bucketferry-<version>-macos-arm64.tar.gz` |

Each package contains `s3bucketferry`, a matching `rclone`, the licenses, and
the User Guide as `USER_GUIDE.html` (one page with every screenshot, readable
offline). Nothing else needs installing.

## Install on Linux

```bash
VER=<version>        # for example 0.3.10
BASE=https://github.com/debkhadanga2023-lgtm/S3BucketFerry/releases/download/v$VER
cd /tmp
curl -fLO $BASE/s3bucketferry-$VER-linux-amd64.tar.gz
curl -fLO $BASE/SHA256SUMS.txt
sha256sum -c --ignore-missing SHA256SUMS.txt      # must print: OK

sudo mkdir -p /opt/s3bucketferry
sudo tar -xzf s3bucketferry-$VER-linux-amd64.tar.gz -C /opt/s3bucketferry --strip-components=1
sudo ln -sf /opt/s3bucketferry/s3bucketferry /usr/local/bin/s3bucketferry
s3bucketferry doctor
```

Then set up the web interface as a service (HTTPS on port 8443 by default):

```bash
sudo s3bucketferry service setup
```

On Windows, extract the zip to a folder such as `C:\S3BucketFerry` and run
`.\s3bucketferry.exe doctor` in PowerShell. Machines without internet access
can be installed from copied files: see the User Guide, section 3.

## Upgrade

```bash
s3bucketferry upgrade --check        # installed and newest versions; changes nothing
sudo s3bucketferry upgrade           # upgrade S3BucketFerry and rclone
sudo s3bucketferry upgrade --rollback
sudo s3bucketferry upgrade --package /tmp/s3bucketferry-<version>-linux-amd64.tar.gz   # offline
```

Every download is checked against its published SHA-256 checksum, and the
previous install is kept for rollback. The upgrade restarts the web interface
service so it runs the new version (it asks for sudo if needed). Details, and
upgrading on Windows, are in the User Guide, section 13.

## Documentation

The [User Guide](docs/USER_GUIDE.md) takes you from installation to a
finished, certified migration, with screenshots, and assumes no previous
experience with S3. The same guide is in every package (`USER_GUIDE.html`) and
in the web interface under **Support > User guide**. Changes in each version
are in [CHANGELOG.md](CHANGELOG.md).

## Features

- **Guided workflow:** scan, dry run, copy, incremental passes while the source
  is still in use, and a one-step cutover.
- **Verification built in:** every copy is checked by checksum, and the cutover
  compares both buckets in full.
- **Migration certificate** (HTML, text, JSON) with per-object results and
  SHA-256 digests of the bucket manifests.
- **Live progress:** workers, throughput, copied, failed and pending counts,
  with failed objects listed by name.
- **Stop and resume** at any time, also after a restart: objects already
  copied are skipped, and with several workers, finished parts of the bucket
  aren't listed again.
- **Safe by design:** source objects are never changed or deleted. Objects on
  the target are deleted only in mirror mode, after a confirmation.
- **No stored secrets:** profiles hold only the names of the environment
  variables with the access keys.
- **Web interface** over HTTPS, with user accounts, three access levels and an
  audit log of every action.
- Single program for Linux, Windows and macOS, with one-command service setup,
  verified upgrades, rollback and offline installation.

## Support

Report problems on the
[Issues page](https://github.com/debkhadanga2023-lgtm/S3BucketFerry/issues).
Attach the job bundle (`s3bucketferry job bundle <id>`), after removing
anything confidential.

The source code is not published in this repository. See [LICENSE](LICENSE)
for the terms of use. rclone is included under its MIT license
(`RCLONE-LICENSE.txt` in each package).
