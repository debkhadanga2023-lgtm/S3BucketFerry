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
# Offline (no internet on this machine): copy the files from a machine that has
# internet, then point the script at them. Nothing is downloaded.
#   sudo ./upgrade.sh --package /tmp/s3bucketferry-0.3.6-linux-amd64.tar.gz
#                                  install this package; SHA256SUMS.txt must be next to it
#   sudo ./upgrade.sh --rclone-zip /tmp/rclone-v1.76.0-linux-amd64.zip
#                                  install this rclone; rclone's SHA256SUMS must be next to it
#
# Other options:
#   --dir DIR          install folder (default: where s3bucketferry is installed, else /opt/s3bucketferry)
#   --service NAME     restart only this systemd service afterwards (default: every
#                      s3bucketferry* service that is running, such as s3bucketferry-ui)
#   --no-restart       change the files only; running services keep the old version
#                      until you restart them (normally upgrade restarts them and,
#                      if needed, asks for sudo first)
#   --yes              do not ask for confirmation
#   --force            upgrade even while a migration seems to be running; with
#                      --package or --rclone-zip, also reinstall the same version
#   --checksums FILE   checksum file for --package or --rclone-zip, if it isn't next to it
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

mode=all; want_version=""; dir=""; service=s3bucketferry-ui; service_given=no; yes=no; force=no; no_restart=no
local_pkg=""; local_rclone=""; sums_file=""
orig_args="$*"; orig=("$@"); backed_up=no
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

say()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

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
    --service) [ $# -ge 2 ] || die "--service needs a name"; service="$2"; service_given=yes; shift ;;
    --service=*) service="${1#*=}"; service_given=yes ;;
    --no-restart) no_restart=yes ;;
    --package) [ $# -ge 2 ] || die "--package needs a file"; local_pkg="$2"; shift ;;
    --package=*) local_pkg="${1#*=}" ;;
    --rclone-zip) [ $# -ge 2 ] || die "--rclone-zip needs a file"; local_rclone="$2"; shift ;;
    --rclone-zip=*) local_rclone="${1#*=}" ;;
    --checksums) [ $# -ge 2 ] || die "--checksums needs a file"; sums_file="$2"; shift ;;
    --checksums=*) sums_file="${1#*=}" ;;
    --yes|-y) yes=yes ;;
    --force) force=yes ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
  shift
done
if [ -n "$want_version" ] && [ "$mode" = all ]; then mode=tool; fi
if [ -n "$local_pkg" ] || [ -n "$local_rclone" ]; then
  [ "$mode" = all ] || die "--package and --rclone-zip cannot be combined with --check, --rollback, --tool-only, --rclone-only or --version"
  [ -n "$local_pkg" ] && [ -n "$local_rclone" ] && [ -n "$sums_file" ] && \
    die "--checksums is for one file; with both --package and --rclone-zip, keep each checksum file next to its download"
  mode=offline
fi

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

# local_sums FILE DEFAULTNAME: the checksum file for a copied download
local_sums() {
  local f
  if [ -n "$sums_file" ]; then f="$sums_file"; else f="$(dirname "$1")/$2"; fi
  [ -f "$f" ] || die "no checksum file for $(basename "$1"): copy $2 from the same release page next to it (or name it with --checksums). It proves the copy is complete and unaltered"
  echo "$f"
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
  command -v pgrep >/dev/null 2>&1 || return 0
  if pgrep -f "^$dir/rclone( |$)" >/dev/null 2>&1; then
    if [ "$force" = yes ]; then
      warn "a migration is running; restarting the web interface stops the tasks it started. Resume them afterwards (job page > Resume)"
      return 0
    fi
    die "a migration is running (rclone from $dir is active). Wait for it to finish, or rerun with --force"
  fi
}

# ferry_services lists the S3BucketFerry services to restart after a change:
# the one named with --service, or else every s3bucketferry* unit.
ferry_services() {
  command -v systemctl >/dev/null 2>&1 || return 0
  if [ "$service_given" = yes ]; then
    service_exists && echo "$service"
    return 0
  fi
  systemctl list-unit-files --type=service --no-legend 's3bucketferry*.service' 2>/dev/null \
    | awk '{print $1}' | sed -n 's/\.service$//p' | sort -u
}

# restart_targets: the services from ferry_services that are running or
# enabled (a stopped, disabled one is left alone).
restart_targets() {
  local svc
  for svc in $(ferry_services); do
    if systemctl is-active --quiet "$svc" || systemctl is-enabled --quiet "$svc" 2>/dev/null; then echo "$svc"; fi
  done
}

# need_root_for_restart makes sure the services can be restarted after the
# change: without root, it runs this script again with sudo (asking for the
# password), before anything is changed. With --no-restart it only warns.
need_root_for_restart() {
  [ "$(id -u)" -eq 0 ] && return 0
  local svcs; svcs=$(restart_targets | tr '\n' ' ' | sed 's/ $//')
  [ -n "$svcs" ] || return 0
  if [ "$no_restart" = yes ]; then
    warn "--no-restart: $svcs will keep running the OLD version until you run:  sudo systemctl restart $svcs"
    return 0
  fi
  if command -v sudo >/dev/null 2>&1 && { [ -t 0 ] || sudo -n true 2>/dev/null; }; then
    say "  the web interface runs as a system service ($svcs); restarting it needs root, so this runs again with sudo"
    local keep=() v
    while IFS= read -r v; do keep+=("$v"); done < <(env | grep '^S3BF_' || true)
    exec sudo env "${keep[@]}" bash "$0" "${orig[@]}" --yes
  fi
  die "the upgrade must restart $svcs so it runs the new version, and that needs root. Run:  ${S3BF_UPGRADE_HINT:-sudo bash $0 $orig_args}
  (or add --no-restart to change only the files and restart later)"
}

writable_or_sudo() {
  need_root_for_restart
  local probe="$dir"
  [ -d "$probe" ] || probe=$(dirname "$dir")
  if [ ! -w "$probe" ]; then
    # S3BF_UPGRADE_HINT is set by "s3bucketferry upgrade"; "bash" works even
    # when this file has lost its execute permission.
    die "no write access to $probe; run with sudo:  ${S3BF_UPGRADE_HINT:-sudo bash $0 $orig_args}"
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
  if [ "$no_restart" = yes ]; then
    local svcs; svcs=$(restart_targets | tr '\n' ' ' | sed 's/ $//')
    [ -z "$svcs" ] || warn "not restarted (--no-restart): $svcs still runs the old version. Restart it:  sudo systemctl restart $svcs"
    warn_manual_ui
    return 0
  fi
  local svc pid any=no
  for svc in $(ferry_services); do
    any=yes
    if ! systemctl is-active --quiet "$svc" && ! systemctl is-enabled --quiet "$svc" 2>/dev/null; then
      say "  $svc is not running and not enabled; not started"
      continue
    fi
    if [ "$(id -u)" -ne 0 ]; then
      warn "cannot restart $svc without root: it still runs the old version. Run:  sudo systemctl restart $svc"
      continue
    fi
    if systemctl restart "$svc"; then
      say "  restarted the $svc service"
    else
      warn "could not restart $svc; check: sudo journalctl -u $svc -n 30"
      continue
    fi
    sleep 1
    if ! systemctl is-active --quiet "$svc"; then
      warn "$svc is not running; check: sudo journalctl -u $svc -n 30"
      continue
    fi
    # Check the restarted service really runs the program just installed.
    pid=$(systemctl show -p MainPID --value "$svc" 2>/dev/null || true)
    if [ -n "$pid" ] && [ "$pid" != 0 ] && [ -e "/proc/$pid/exe" ]; then
      if [ "/proc/$pid/exe" -ef "$dir/s3bucketferry" ]; then
        say "  $svc is running $("$dir/s3bucketferry" --version 2>/dev/null || echo 'the new version')"
      else
        warn "$svc is running, but not the program in $dir (its ExecStart points elsewhere); check: systemctl cat $svc"
      fi
    else
      say "  $svc is running"
    fi
  done
  [ "$any" = yes ] || true
  warn_manual_ui
}

# A web interface started by hand (not as a service) keeps the old program
# until it is stopped and started again.
warn_manual_ui() {
  command -v pgrep >/dev/null 2>&1 || return 0
  local p cg
  for p in $(pgrep -f "^$dir/s3bucketferry ui( |$)" 2>/dev/null || true); do
    cg=$(cat "/proc/$p/cgroup" 2>/dev/null || true)
    case "$cg" in *s3bucketferry*.service*) continue ;; esac
    warn "a web interface started by hand (process $p) still runs the old version; stop it (kill $p) and start it again"
  done
}

# The web interface service can be set up with "s3bucketferry service setup"
# (0.3.5 and later): HTTPS on 8443 or HTTP on 8080, and which certificate.
# After an upgrade, offer it for a service that was not written by it.
offer_service_setup() {
  service_exists || return 0
  [ -x "$dir/s3bucketferry" ] || return 0
  "$dir/s3bucketferry" --help 2>/dev/null | grep -q "service setup" || return 0
  local unit
  unit=$(systemctl show -p FragmentPath --value "$service" 2>/dev/null || true)
  [ -n "$unit" ] && [ -r "$unit" ] || return 0
  grep -q 'Written by "s3bucketferry service setup"' "$unit" && return 0
  say
  say "The $service service can now be set up with one command: HTTPS on port 8443"
  say "(recommended) or HTTP on port 8080, with the generated certificate or your own."
  if [ "$yes" = yes ] || [ ! -t 0 ] || [ "$(id -u)" -ne 0 ]; then
    say "  to set it up:  sudo s3bucketferry service setup"
    return 0
  fi
  local a
  read -r -p "Set it up now? [Y/n] " a || a=n
  case "$a" in
    ""|y|Y|yes|YES) ;;
    *) say "  to set it up later:  sudo s3bucketferry service setup"; return 0 ;;
  esac
  "$dir/s3bucketferry" service setup --service "$service" \
    || warn "service setup did not finish; run it again with:  sudo s3bucketferry service setup"
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
  local svc
  for svc in $(ferry_services); do
    if systemctl is-active --quiet "$svc"; then say "service: $svc (running)"; else say "service: $svc (not running)"; fi
  done
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
  install_package "$tmp/$pkg.tar.gz" "$pkg" "$target"
}

# install_package TARBALL PKGNAME VERSION: unpack a verified package and install it
install_package() {
  local tarball="$1" pkg="$2" target="$3" tmp="$work/unpack"
  mkdir -p "$tmp"
  tar -xzf "$tarball" -C "$tmp"
  [ -x "$tmp/$pkg/s3bucketferry" ] || die "the package has no s3bucketferry program"
  local got
  got=$("$tmp/$pkg/s3bucketferry" --version | awk '{print $2}')
  [ "$got" = "$target" ] || die "the program in the package reports version $got, expected $target"

  if [ -d "$dir" ]; then backup; else mkdir -p "$dir"; fi
  local f
  for f in "$tmp/$pkg"/*; do
    if [ -d "$f" ]; then # a folder in a future package: replace it whole
      rm -rf "${dir:?}/$(basename "$f")"
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
  if curl -fsSL -o "$tmp/COPYING" "$RCLONE_RAW/$rn/COPYING"; then
    install -m 644 "$tmp/COPYING" "$dir/RCLONE-LICENSE.txt"
  else
    warn "could not refresh RCLONE-LICENSE.txt"
  fi
  echo "$rn" > "$tmp/RCLONE-VERSION.txt" && install -m 644 "$tmp/RCLONE-VERSION.txt" "$dir/RCLONE-VERSION.txt"
  say "  installed: $("$dir/rclone" version | head -1)"
  restart_service
}

# ---- offline: files copied to this machine ------------------------------

do_tool_offline() {
  local f="$local_pkg" name target os arch pos parch ti
  [ -f "$f" ] || die "$f does not exist"
  name=$(basename "$f")
  [[ "$name" =~ ^s3bucketferry-([0-9][0-9A-Za-z.+-]*)-(linux|macos)-(amd64|arm64)\.tar\.gz$ ]] \
    || die "$name is not an S3BucketFerry Linux or macOS package (expected s3bucketferry-<version>-<system>-<cpu>.tar.gz)"
  target="${BASH_REMATCH[1]}"; pos="${BASH_REMATCH[2]}"; parch="${BASH_REMATCH[3]}"
  local pf; pf=$(platform) || exit 1
  read -r os arch <<<"$pf"
  [ "$pos-$parch" = "$os-$arch" ] || die "$name is for $pos/$parch, but this machine is $os/$arch; copy s3bucketferry-$target-$os-$arch.tar.gz instead"
  ti=$(tool_installed)
  if [ "$ti" = "$target" ] && [ "$force" != yes ]; then
    say "S3BucketFerry $target is already installed (use --force to reinstall it)"
    return 0
  fi
  say "S3BucketFerry: ${ti:-not installed} -> $target ($os/$arch), from $f"
  if [ -n "$ti" ] && newer "$ti" "$target"; then say "  this is an older version than the one installed"; fi
  say "  install folder: $dir"
  local sums; sums=$(local_sums "$f" SHA256SUMS.txt)
  verify "$f" "$sums"
  confirm "Install S3BucketFerry $target?"
  writable_or_sudo
  check_busy
  install_package "$f" "${name%.tar.gz}" "$target"
}

do_rclone_offline() {
  local f="$local_rclone" name rn os arch ri tmp
  [ -f "$f" ] || die "$f does not exist"
  [ -d "$dir" ] || die "$dir does not exist; install S3BucketFerry first"
  name=$(basename "$f" .zip)
  [[ "$name" =~ ^rclone-(v[0-9][0-9A-Za-z.+-]*)-(linux|osx)-(amd64|arm64)$ ]] \
    || die "$(basename "$f") is not an rclone download (expected rclone-v<version>-<system>-<cpu>.zip)"
  rn="${BASH_REMATCH[1]}"
  local pf; pf=$(platform) || exit 1
  read -r os arch <<<"$pf"
  [ "$os" = macos ] && os=osx
  [ "${BASH_REMATCH[2]}-${BASH_REMATCH[3]}" = "$os-$arch" ] \
    || die "$(basename "$f") is for ${BASH_REMATCH[2]}/${BASH_REMATCH[3]}, but this machine is $os/$arch; copy rclone-$rn-$os-$arch.zip instead"
  ri=$(rclone_installed)
  if [ "$ri" = "$rn" ] && [ "$force" != yes ]; then
    say "rclone $rn is already installed (use --force to reinstall it)"
    return 0
  fi
  say "rclone: ${ri:-not installed} -> $rn, from $f"
  local sums; sums=$(local_sums "$f" SHA256SUMS)
  verify "$f" "$sums"
  confirm "Install rclone $rn?"
  writable_or_sudo
  check_busy
  need unzip
  tmp="$work/rclone"; mkdir -p "$tmp"
  unzip -q "$f" -d "$tmp"
  [ -x "$tmp/$name/rclone" ] || die "the zip has no $name/rclone"
  "$tmp/$name/rclone" version >/dev/null || die "this rclone does not run on this machine"
  backup
  install -m 755 "$tmp/$name/rclone" "$dir/rclone"
  echo "$rn" > "$tmp/RCLONE-VERSION.txt" && install -m 644 "$tmp/RCLONE-VERSION.txt" "$dir/RCLONE-VERSION.txt"
  say "  installed: $("$dir/rclone" version | head -1)"
  say "  (RCLONE-LICENSE.txt was kept; rclone's license is MIT and unchanged between releases)"
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

if [ "$mode" = offline ] || [ "$mode" = rollback ]; then need tar awk sed sort; else need curl tar awk sed sort; fi
dir=$(find_dir)
case "$mode" in
  check) do_check ;;
  tool) do_tool; offer_service_setup ;;
  rclone) do_rclone ;;
  rollback) do_rollback ;;
  offline)
    defer_restart=yes; restart_pending=no
    [ -z "$local_pkg" ] || do_tool_offline
    [ -z "$local_rclone" ] || do_rclone_offline
    defer_restart=no
    if [ "$restart_pending" = yes ]; then restart_service; fi
    say
    say "installed: $("$dir/s3bucketferry" --version 2>/dev/null || echo unknown), $("$dir/rclone" version 2>/dev/null | head -1 || echo 'rclone unknown')"
    [ -z "$local_pkg" ] || offer_service_setup
    ;;
  all)
    defer_restart=yes; restart_pending=no
    do_tool
    do_rclone
    defer_restart=no
    if [ "$restart_pending" = yes ]; then restart_service; fi
    say
    do_check
    offer_service_setup
    ;;
esac
