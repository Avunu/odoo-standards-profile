#!/usr/bin/env bash
# Validate this profile against one odoo-nix:
#
#   1. `odoo-nix profile validate profile.toml --templates templates`: the schema, `extends`,
#      the version range, and every managed file rendered for odoo-nix-tools' own fixture
#      checkouts;
#   2. for each of odoo-nix's two fixtures, standards-project and standards-addons:
#      a. `odoo-nix profile show --format json` of a copy of the fixture that selects this
#         profile, compared with the committed resolved.<shape>.snapshot.json, so an odoo-nix
#         release that would change any value of ours fails here first;
#      b. an offline `odoo-nix sync --write` of another copy (the profile in-repo, as
#         `./.standards-profile`, with the fixture's locks from tests/fixtures/standards-locks),
#         then `sync --check`: every managed file renders with our values;
#   3. fleet.json: the engine's fleet schema (`odoo-nix repo targets`, which validates the
#      file before it clones anything; git is given no network transport here), then the
#      rules odoo-nix doesn't know (scripts/check_fleet.py).
#
# The [tool.odoo-nix] table is in pyproject.toml in a project and in nix/pyproject.toml in an
# addon repository. An odoo-nix-tools without the core's per-checkout config file (CR1) reads
# only the root one and reports the addons fixture as not opted in: while no
# resolved.addons.snapshot.json is committed, that fixture is then skipped with a warning. Once
# it is committed, the addons fixture is required.
#
# Usage: scripts/check.sh [--update | --additive]
#   --update    rewrite resolved.project.snapshot.json and resolved.addons.snapshot.json
#               (each fixture the engine can resolve) instead of comparing them
#   --additive  accept keys a snapshot doesn't have, other than a module that resolves on
#               (scripts/compare_snapshot.py): every value it records must resolve the same.
#               The validate workflow's `latest` job uses this, since a newer odoo-nix than
#               the pinned one may add options.
#
# Environment:
#   ODOO_NIX              the odoo-nix CLI to run: a command, split on spaces (default: the
#                         one flake.lock pins, built with nix)
#   ODOO_NIX_SRC          the matching odoo-nix source tree, with the fixtures under
#                         tests/fixtures/ (default: the one flake.lock pins)
#   ODOO_NIX_SKIP_ADDONS  1: skip the standards-addons fixture, with a warning, even when its
#                         snapshot is committed
#
# Before odoo-nix 2.3.0 exists, an odoo-nix-tools build reports 2.2.0 (the last release
# without the standards engine), which profile.toml's `requires-odoo-nix` floor of 2.3 would
# exclude (exit 3). Against such an unreleased build the checks run on a copy without that
# one line, with a warning; against any release the file is checked exactly as committed.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# The first odoo-nix release with the standards engine: any odoo-nix-tools below it is a
# development build (see above). Remove this and the branch below once flake.lock pins
# v2.3.0 (README.md, "Before the first release", item 1).
first_release=2.3.0

update=0
additive=0
case "${1:-}" in
  --update) update=1 ;;
  --additive) additive=1 ;;
  "") ;;
  *) echo "usage: scripts/check.sh [--update | --additive]" >&2; exit 2 ;;
esac

note() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::$1::$2"; else echo "$1: $2" >&2; fi
}

work="$(mktemp -d)"
# A copy of a fixture from the Nix store is read-only until copy_fixture makes it writable:
# make sure all of it is before removing it.
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT

if [ -n "${ODOO_NIX:-}" ]; then
  read -r -a odoo_nix <<< "$ODOO_NIX"
else
  [ -f flake.lock ] || {
    echo "error: no flake.lock: the odoo-nix release flake.nix pins is not locked yet." >&2
    echo "Set ODOO_NIX (and ODOO_NIX_SRC) to a development build; see README.md." >&2
    exit 2
  }
  nix build .#odoo-nix --out-link "$work/odoo-nix"
  odoo_nix=("$work/odoo-nix/bin/odoo-nix")
fi
if [ -z "${ODOO_NIX_SRC:-}" ]; then
  [ -f flake.lock ] || {
    echo "error: no flake.lock: the odoo-nix release flake.nix pins is not locked yet." >&2
    echo "Set ODOO_NIX_SRC (with ODOO_NIX) to a development checkout; see README.md." >&2
    exit 2
  }
  ODOO_NIX_SRC="$(nix eval --raw .#lib.odoo-nix-src)"
fi
fixtures="$ODOO_NIX_SRC/tests/fixtures"
# config_file <shape>: the file the fixture's [tool.odoo-nix] table is in.
config_file() {
  case "$1" in
    project) echo pyproject.toml ;;
    addons) echo nix/pyproject.toml ;;
  esac
}
shapes=(project addons)
for shape in "${shapes[@]}"; do
  config="$fixtures/standards-$shape/$(config_file "$shape")"
  [ -f "$config" ] || { echo "error: no fixture at $config" >&2; exit 2; }
done

# A repository of its own for each copy: none of the user's git configuration applies.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=profile-check GIT_AUTHOR_EMAIL=profile-check@example.org
export GIT_COMMITTER_NAME=profile-check GIT_COMMITTER_EMAIL=profile-check@example.org

version="$("${odoo_nix[@]}" --version)"
echo "odoo-nix-tools $version (fixtures from $ODOO_NIX_SRC)"

# The profile directory every check reads: profile.toml, templates/ and assets/.
profile="$work/profile"
mkdir -p "$profile"
if [ "$(printf '%s\n' "$version" "$first_release" | sort -V | head -n 1)" != "$first_release" ]; then
  note warning "odoo-nix-tools $version is a development build before $first_release: checking profile.toml without its requires-odoo-nix line"
  grep -v '^requires-odoo-nix[[:space:]]*=' profile.toml > "$profile/profile.toml"
else
  cp profile.toml "$profile/profile.toml"
fi
for dir in templates assets; do
  if [ -d "$dir" ]; then
    cp -r "$dir" "$profile/$dir"
  fi
done

echo "== profile validate"
"${odoo_nix[@]}" profile validate "$profile/profile.toml" --templates "$profile/templates"

# copy_fixture <shape> <dest> <profile value>: a writable copy of the fixture whose
# [tool.odoo-nix] table selects <profile value>, with the fixture's locks, in a fresh repo.
copy_fixture() {
  local config locks f
  config="$2/$(config_file "$1")"
  cp -r "$fixtures/standards-$1" "$2"
  # A fixture from the Nix store (the default ODOO_NIX_SRC) copies read-only: make the copy
  # writable before anything is added to it.
  chmod -R u+w "$2"
  # The locks odoo-nix's own fixture checks use: built with every tool its example-org
  # profile turns on, which is every module, so they cover ours (a lock may hold more tools
  # than the profile renders).
  locks="$fixtures/standards-locks/standards-$1/example-org"
  for f in tools/uv.lock package-lock.json; do
    if [ -f "$locks/$f" ]; then
      mkdir -p "$(dirname "$2/$f")"
      cp "$locks/$f" "$2/$f"
    fi
  done
  # -i with a suffix, then the backup removed: GNU and BSD sed both take that form.
  sed -i.bak "s#^profile = .*\$#profile = \"$3\"#" "$config"
  rm -f "$config.bak"
  grep -qx "profile = \"$3\"" "$config" || {
    echo "error: the standards-$1 fixture's $(config_file "$1") has no profile line to point at this profile" >&2
    exit 2
  }
  git -C "$2" init -q -b main
  git -C "$2" add -A
}

for shape in "${shapes[@]}"; do
  snapshot="resolved.$shape.snapshot.json"

  if [ "$shape" = addons ] && [ "${ODOO_NIX_SKIP_ADDONS:-}" = 1 ]; then
    note warning "standards-addons fixture skipped (ODOO_NIX_SKIP_ADDONS=1)"
    continue
  fi

  echo "== resolved configuration of the standards-$shape fixture"
  copy_fixture "$shape" "$work/$shape-show" "github:Avunu/odoo-standards-profile/v1"
  status=0
  (cd "$work/$shape-show" && "${odoo_nix[@]}" profile show --format json --profile-path "$profile") \
    > "$work/resolved.$shape.json" 2> "$work/show.$shape.err" || status=$?
  if [ "$status" != 0 ]; then
    cat "$work/show.$shape.err" >&2
    if [ "$shape" = addons ] && [ ! -f "$snapshot" ] && grep -q "has not opted in" "$work/show.$shape.err"; then
      note warning "odoo-nix-tools $version does not read [tool.odoo-nix] from nix/pyproject.toml yet (core CR1): standards-addons fixture skipped, and no $snapshot is written"
      continue
    fi
    echo "error: profile show of the standards-$shape fixture failed (exit $status)" >&2
    exit 1
  fi
  if [ "$update" = 1 ]; then
    cp "$work/resolved.$shape.json" "$snapshot"
    echo "wrote $snapshot"
  elif [ ! -f "$snapshot" ]; then
    echo "error: $snapshot does not exist; run scripts/check.sh --update and commit it." >&2
    exit 1
  elif diff -u "$snapshot" "$work/resolved.$shape.json"; then
    echo "matches $snapshot"
  elif [ "$additive" = 1 ]; then
    python3 -I "$root/scripts/compare_snapshot.py" "$snapshot" "$work/resolved.$shape.json" || {
      echo "error: odoo-nix-tools $version changes the resolved $shape configuration beyond added options (above)." >&2
      echo "Taking this release means updating the profile or the snapshots with it on purpose." >&2
      exit 1
    }
  else
    echo "error: the resolved $shape configuration differs from $snapshot (diff above)." >&2
    echo "If the change is intended, run scripts/check.sh --update and commit the result." >&2
    exit 1
  fi

  echo "== offline sync of the standards-$shape fixture"
  copy_fixture "$shape" "$work/$shape-sync" "./.standards-profile"
  cp -r "$profile" "$work/$shape-sync/.standards-profile"
  git -C "$work/$shape-sync" add -A
  git -C "$work/$shape-sync" commit -qm fixture
  # The fixture pins this same odoo-nix only by flake.lock; skew is expected here.
  (cd "$work/$shape-sync" && ODOO_NIX_ALLOW_SKEW=1 "${odoo_nix[@]}" sync --write --offline)
  git -C "$work/$shape-sync" add -A
  (cd "$work/$shape-sync" && ODOO_NIX_ALLOW_SKEW=1 "${odoo_nix[@]}" sync --check)
done

echo "== fleet.json"
# `repo targets` validates the whole file against odoo-nix's composed fleet schema (exit 2)
# before it clones the first repository. With no git transport but file allowed, that clone
# fails at once (exit 3), which means the file passed; nothing reaches the network.
# This relies on that exit code and on the clone error naming `git clone`: a change to
# either fails here loudly, never silently. Switch to an offline fleet validate command
# once odoo-nix or the standards core ships one.
status=0
GIT_ALLOW_PROTOCOL="file" "${odoo_nix[@]}" repo targets --all --fleet "$root/fleet.json" \
  > /dev/null 2> "$work/fleet.err" || status=$?
if [ "$status" = 3 ] && grep -q "git clone" "$work/fleet.err"; then
  echo "fleet.json: valid against the odoo-nix fleet schema"
else
  cat "$work/fleet.err" >&2
  echo "error: odoo-nix repo targets refused fleet.json (exit $status)" >&2
  exit 1
fi
python3 -I "$root/scripts/check_fleet.py" "$root/fleet.json" "$root/profile.toml"
