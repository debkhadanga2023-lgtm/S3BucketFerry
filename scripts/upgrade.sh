#!/usr/bin/env bash
# S3BucketFerry upgrade helper.
#
# Checks for and installs the newest S3BucketFerry release and the newest
# rclone, verifying every download against its published SHA-256 checksum.
# Before changing anything it keeps a copy of the current install, so one
# command puts the old version back.
#
# Usage (run with sudo when the install folder belongs to root):
#   sudo ./upgrade.sh              upgrade S3BucketFerry, then rclone, if newer versions exist
#   sudo ./upgrade.sh --check      only show installed and newest versions; change nothing
#   sudo ./upgrade.sh --rclone-only    upgrade only rclone
#   sudo ./upgrade.sh --tool-only      upgrade only S3BucketFerry (with the rclone in its package)
#   sudo ./upgrade.sh --version 0.3.2  install this S3BucketFerry version (also downgrades)
#   sudo ./upgrade.sh --rollback   put back the install that was there before the last upgrade
#
# Other options:
#   --dir DIR          install folder (default: where s3bucketferry is installed, else /opt/s3bucketferry)
#   --service NAME     systemd service to restart afterwards (default: s3bucketferry-ui, if it exists)
#   --yes              do not ask for confirmation
#   --force            upgrade even while a migration seems to be running
#
# Your profiles, jobs, reports, certificates and users live in your own
# config folder (S3BF_HOME, default ~/.config/s3bucketferry) and are never touched.
set -euo pipefail

REPO="${S3BF_REPO:-debkhadanga2023-lgtm/S3BucketFerry}"
API="${S3BF_UPGRADE_API:-https://api.github.com/repos/$REPO/releases?per_page=20}"
DOWNLOAD="${S3BF_UPGRADE_DOWNLOAD:-https://github.com/$REPO/releases/download}"
LATEST_PAGE="${S3BF_UPGRADE_LATEST_PAGE:-https://github.com/$REPO/releases/latest}"
RCLONE_VERSION_URL="${S3BF_RCLONE_VERSION_URL:-https://downloads.rclone.org/version.txt}"
RCLONE_API="${S3BF_RCLONE_API_URL:-https://api.github.com/repos/rclone/rclone/releases/latest}"
RCLONE_BASE="${S3BF_RCLONE_RELEASE_BASE:-https://github.com/rclone/rclone/releases/download}"
RCLONE_RAW="${S3BF_RCLONE_RAW_BASE:-https://raw.githubusercontent.com/rclone/rclone}"

mode=all; want_version=""; dir=""; service=s3bucketferry-ui; yes=no; force=no
orig_args="$*"; backed_up=no
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

say()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode=check ;;
    --rclone-only) mode=rclone ;;
    --tool-only) mode=tool ;;
    --rollback) mode=rollback ;;
    --version) [ $# -ge 2 ] || die "--version needs a value, e.g. 0.3.2"; want_version="${2#v}"; shift ;;
    --version=*) want_version="${1#*=}"; want_version="${want_version#v}" ;;
    --dir) [ $# -ge 2 ] || die "--dir needs a folder"; dir="$2"; shift ;;
    --dir=*) dir="${1#*=}" ;;
    --service) [ $# -ge 2 ] || die "--service needs a name"; service="$2"; shift ;;
    --service=*) service="${1#*=}" ;;
    --yes|-y) yes=yes ;;
    --force) force=yes ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
  shift
done
if [ -n "$want_version" ] && [ "$mode" = all ]; then mode=tool; fi

# ---- helpers ------------------------------------------------------------

need() {
  local missing=()
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  if [ ${#missing[@]} -gt 0 ]; then
    die "missing programs: ${missing[*]} (on Ubuntu/Debian: sudo apt install -y ${missing[*]})"
  fi
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# verify FILE SUMSFILE: the file's name must be listed in SUMSFILE with a matching hash
verify() {
  local f="$1" sums="$2" name want got
  name=$(basename "$f")
  want=$(awk -v f="$name" '$2 == f || $2 == "*" f { print $1; exit }' "$sums")
  [ -n "$want" ] || die "$name is not listed in the published checksums"
  got=$(sha256 "$f")
  [ "$want" = "$got" ] || die "checksum mismatch for $name (expected $want, got $got); nothing was changed"
  say "  checksum OK: $name"
}

# newer A B: true when version A is newer than version B (v prefixes ignored)
newer() {
  local a="${1#v}" b="${2#v}"
  [ "$a" != "$b" ] && [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -1)" = "$a" ]
}

platform() {
  local os arch
  case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=macos ;;
    *) die "unsupported system $(uname -s); download the package by hand from https://github.com/$REPO/releases" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) die "unsupported CPU $(uname -m)" ;;
  esac
  echo "$os $arch"
}

confirm() {
  [ "$yes" = yes ] && return 0
  if [ ! -t 0 ]; then return 0; fi
  local r
  read -r -p "$1 [Y/n] " r
  case "$r" in ""|y|Y|yes|YES) return 0 ;; *) say "nothing changed"; exit 0 ;; esac
}

find_dir() {
  if [ -n "$dir" ]; then echo "$dir"; return; fi
  local p
  if p=$(command -v s3bucketferry 2>/dev/null); then
    p=$(readlink -f "$p" 2>/dev/null || echo "$p")
    dirname "$p"
    return
  fi
  echo /opt/s3bucketferry
}

tool_installed() {
  if [ -x "$dir/s3bucketferry" ]; then "$dir/s3bucketferry" --version 2>/dev/null | awk '{print $2}'; fi
}

rclone_installed() {
  if [ -x "$dir/rclone" ]; then "$dir/rclone" version 2>/dev/null | awk 'NR==1 {print $2}'; fi
}

tool_newest() {
  local tag
  tag=$(curl -fsSL "$API" 2>/dev/null | tr ',' '\n' | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)
  if [ -z "$tag" ]; then
    # API unavailable or rate limited: the releases/latest page redirects to the newest full release
    tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$LATEST_PAGE" 2>/dev/null | sed -n 's#.*/tag/\(v[^/]*\)$#\1#p' || true)
  fi
  echo "${tag#v}"
}

rclone_newest() {
  local v
  v=$(curl -fsSL "$RCLONE_VERSION_URL" 2>/dev/null | awk '{print $2; exit}' || true)
  if [ -z "$v" ]; then
    v=$(curl -fsSL "$RCLONE_API" 2>/dev/null | tr ',' '\n' | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)
  fi
  echo "$v"
}

service_exists() {
  command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files "$service.service" 2>/dev/null | grep -q "^$service.service"
}

service_active() {
  service_exists && systemctl is-active --quiet "$service"
}

# A migration started from the CLI or the web UI runs rclone from the install folder.
check_busy() {
  [ "$force" = yes ] && return 0
  command -v pgrep >/dev/null 2>&1 || return 0
  if pgrep -f "^$dir/rclone( |$)" >/dev/null 2>&1; then
    die "a migration is running (rclone from $dir is active). Wait for it to finish, or rerun with --force"
  fi
}

writable_or_sudo() {
  local probe="$dir"
  [ -d "$probe" ] || probe=$(dirname "$dir")
  if [ ! -w "$probe" ]; then
    die "no write access to $probe; run with sudo:  sudo $0 $orig_args"
  fi
}

# backup keeps one copy of the install as it was before this run, so
# --rollback returns to it even when both the tool and rclone were upgraded.
backup() {
  local prev="$dir.previous"
  [ "$backed_up" = yes ] && return 0
  backed_up=yes
  rm -rf "$prev"
  cp -a "$dir" "$prev"
  say "  backup of the current install: $prev"
}

restart_service() {
  [ "${defer_restart:-no}" = yes ] && { restart_pending=yes; return 0; }
  if service_exists; then
    if [ "$(id -u)" -eq 0 ]; then
      systemctl restart "$service" && say "  restarted the $service service" || warn "could not restart $service; check: sudo journalctl -u $service -n 30"
      sleep 1
      systemctl is-active --quiet "$service" && say "  $service is running" || warn "$service is not running; check: sudo journalctl -u $service -n 30"
    else
      say "  restart the web UI to use the new version:  sudo systemctl restart $service"
    fi
  fi
}

# ---- the steps ----------------------------------------------------------

do_check() {
  local ti tn ri rn
  ti=$(tool_installed); tn=$(tool_newest)
  ri=$(rclone_installed); rn=$(rclone_newest)
  say "install folder: $dir"
  printf '%-15s %-12s %-12s %s\n' "" "installed" "newest" ""
  local s
  if [ -z "$tn" ]; then s="could not reach GitHub"
  elif [ -z "$ti" ]; then s="not installed here"
  elif newer "$tn" "$ti"; then s="UPGRADE AVAILABLE"
  else s="up to date"; fi
  printf '%-15s %-12s %-12s %s\n' "S3BucketFerry" "${ti:--}" "${tn:--}" "$s"
  if [ -z "$rn" ]; then s="could not reach rclone.org or GitHub"
  elif [ -z "$ri" ]; then s="not installed here"
  elif newer "$rn" "$ri"; then s="UPGRADE AVAILABLE"
  else s="up to date"; fi
  printf '%-15s %-12s %-12s %s\n' "rclone" "${ri:--}" "${rn:--}" "$s"
  if service_exists; then
    if service_active; then say "web UI service: $service (running)"; else say "web UI service: $service (not running)"; fi
  fi
}

do_tool() {
  local ti target os arch pkg tmp
  ti=$(tool_installed)
  if [ -n "$want_version" ]; then
    target="$want_version"
  else
    target=$(tool_newest)
    [ -n "$target" ] || die "could not find the newest release on GitHub (no internet, or rate limited). Try again later, or use --version"
  fi
  if [ -z "$want_version" ] && [ -n "$ti" ] && ! newer "$target" "$ti"; then
    say "S3BucketFerry $ti is up to date"
    return 0
  fi
  local pf; pf=$(platform) || exit 1
  read -r os arch <<<"$pf"
  pkg="s3bucketferry-$target-$os-$arch"
  say "S3BucketFerry: ${ti:-not installed} -> $target ($os/$arch)"
  say "  install folder: $dir"
  confirm "Upgrade S3BucketFerry to $target?"
  writable_or_sudo
  check_busy

  tmp="$work/tool"; mkdir -p "$tmp"
  say "  downloading $pkg.tar.gz"
  curl -fsSL -o "$tmp/$pkg.tar.gz" "$DOWNLOAD/v$target/$pkg.tar.gz" \
    || die "download failed: $DOWNLOAD/v$target/$pkg.tar.gz (does release v$target exist?)"
  curl -fsSL -o "$tmp/SHA256SUMS.txt" "$DOWNLOAD/v$target/SHA256SUMS.txt" || die "could not download SHA256SUMS.txt"
  verify "$tmp/$pkg.tar.gz" "$tmp/SHA256SUMS.txt"
  tar -xzf "$tmp/$pkg.tar.gz" -C "$tmp"
  [ -x "$tmp/$pkg/s3bucketferry" ] || die "the package has no s3bucketferry program"
  local got
  got=$("$tmp/$pkg/s3bucketferry" --version | awk '{print $2}')
  [ "$got" = "$target" ] || die "the downloaded program reports version $got, expected $target"

  if [ -d "$dir" ]; then backup; else mkdir -p "$dir"; fi
  local f
  for f in "$tmp/$pkg"/*; do
    if [ -d "$f" ]; then # a folder in a future package: replace it whole
      rm -rf "$dir/$(basename "$f")"
      cp -R "$f" "$dir/"
      continue
    fi
    case "$(basename "$f")" in
      s3bucketferry|rclone|upgrade.sh) install -m 755 "$f" "$dir/" ;;
      *) install -m 644 "$f" "$dir/" ;;
    esac
  done
  if [ ! -e /usr/local/bin/s3bucketferry ] && [ -w /usr/local/bin ]; then
    ln -sf "$dir/s3bucketferry" /usr/local/bin/s3bucketferry
  fi
  say "  installed: $("$dir/s3bucketferry" --version), $("$dir/rclone" version 2>/dev/null | head -1)"
  restart_service
}

do_rclone() {
  local ri rn os arch name tmp
  ri=$(rclone_installed); rn=$(rclone_newest)
  [ -n "$rn" ] || die "could not find the newest rclone version (no internet?)"
  if [ -n "$ri" ] && ! newer "$rn" "$ri"; then
    say "rclone $ri is up to date"
    return 0
  fi
  [ -d "$dir" ] || die "$dir does not exist; install S3BucketFerry first"
  local pf; pf=$(platform) || exit 1
  read -r os arch <<<"$pf"
  [ "$os" = macos ] && os=osx
  name="rclone-$rn-$os-$arch"
  say "rclone: ${ri:-not installed} -> $rn"
  confirm "Upgrade rclone to $rn?"
  writable_or_sudo
  check_busy
  need unzip

  tmp="$work/rclone"; mkdir -p "$tmp"
  say "  downloading $name.zip"
  curl -fsSL -o "$tmp/$name.zip" "$RCLONE_BASE/$rn/$name.zip" || die "download failed: $RCLONE_BASE/$rn/$name.zip"
  curl -fsSL -o "$tmp/SHA256SUMS" "$RCLONE_BASE/$rn/SHA256SUMS" || die "could not download rclone's SHA256SUMS"
  verify "$tmp/$name.zip" "$tmp/SHA256SUMS"
  unzip -q "$tmp/$name.zip" -d "$tmp"
  "$tmp/$name/rclone" version >/dev/null || die "the downloaded rclone does not run on this machine"

  backup
  install -m 755 "$tmp/$name/rclone" "$dir/rclone"
  curl -fsSL -o "$tmp/COPYING" "$RCLONE_RAW/$rn/COPYING" && install -m 644 "$tmp/COPYING" "$dir/RCLONE-LICENSE.txt" || warn "could not refresh RCLONE-LICENSE.txt"
  echo "$rn" > "$tmp/RCLONE-VERSION.txt" && install -m 644 "$tmp/RCLONE-VERSION.txt" "$dir/RCLONE-VERSION.txt"
  say "  installed: $("$dir/rclone" version | head -1)"
  restart_service
}

do_rollback() {
  local prev="$dir.previous" old
  [ -d "$prev" ] || die "no previous install to go back to ($prev does not exist)"
  say "current : $("$dir/s3bucketferry" --version 2>/dev/null || echo unknown), $("$dir/rclone" version 2>/dev/null | head -1 || echo 'rclone unknown')"
  say "previous: $("$prev/s3bucketferry" --version 2>/dev/null || echo unknown), $("$prev/rclone" version 2>/dev/null | head -1 || echo 'rclone unknown')"
  confirm "Go back to the previous install?"
  writable_or_sudo
  check_busy
  old="$dir.rollback-$$"
  mv "$dir" "$old"
  mv "$prev" "$dir"
  mv "$old" "$prev"
  say "  restored. The version you rolled back from is kept in $prev (run --rollback again to return to it)"
  restart_service
}

need curl tar awk sed sort
dir=$(find_dir)
case "$mode" in
  check) do_check ;;
  tool) do_tool ;;
  rclone) do_rclone ;;
  rollback) do_rollback ;;
  all)
    defer_restart=yes; restart_pending=no
    do_tool
    do_rclone
    defer_restart=no
    if [ "$restart_pending" = yes ]; then restart_service; fi
    say
    do_check
    ;;
esac
