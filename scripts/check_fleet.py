"""Check fleet.json for the rules odoo-nix's fleet schema doesn't express.

fleet.json is the list `odoo-nix repo apply|audit|rollout|targets --all --fleet` iterates.
scripts/check.sh first validates it against odoo-nix's own composed fleet schema (the core's
`fleet-entry-core` with odoo-nix-tools' entry: `repo`, `shape`, `branches`, `private`,
optional `integration_branch`, `documentation` and `profile`). This adds what the schema
can't say about the Avunu fleet:

- no repository is listed twice (GitHub compares names case-insensitively);
- the top-level `profile` is this repository's v1 branch;
- the branches follow the release flow `develop+series`: the integration branch is
  `integration_branch` when set, else `branches[0]`, and is one of `branches`; in an addon
  repository it is not a series branch, every other branch is one (`<major>.0`), and there is
  at least one; a project has exactly one branch;
- no branch is listed twice;
- repositories outside the profile's [org] github-owner are reported, as notices.

Usage: python3 -I scripts/check_fleet.py fleet.json profile.toml
"""

import json
import os
import re
import sys
import tomllib

PROFILE = "github:Avunu/odoo-standards-profile/v1"
SERIES = re.compile(r"^\d+\.0$")
SHAPES = ("project", "addons")


def check_entry(where: str, entry: dict) -> list[str]:
    errors: list[str] = []
    shape = entry.get("shape")
    branches = entry.get("branches")
    if not isinstance(branches, list) or not all(isinstance(b, str) for b in branches):
        return [f"{where}: branches must be a list of branch names"]
    if len(set(branches)) != len(branches):
        errors.append(f"{where}: a branch is listed twice")
    integration = entry.get("integration_branch") or (branches[0] if branches else "")
    if integration not in branches:
        errors.append(f"{where}: the integration branch {integration!r} is not one of branches")
    if shape == "addons":
        if SERIES.match(integration):
            errors.append(
                f"{where}: the integration branch {integration!r} is a series branch;"
                " pull requests go to develop, and the series branch follows it"
            )
        series = [b for b in branches if b != integration]
        errors.extend(
            f"{where}: series branch {name!r} is not <major>.0" for name in series if not SERIES.match(name)
        )
        if not series:
            errors.append(f"{where}: an addon repository needs at least one series branch")
    elif shape == "project" and len(branches) != 1:
        errors.append(f"{where}: a project has exactly one branch, its integration branch")
    return errors


def check(fleet: dict) -> list[str]:
    errors: list[str] = []
    if fleet.get("profile") != PROFILE:
        errors.append(f"profile must be {PROFILE!r}")
    repos = fleet.get("repos")
    if not isinstance(repos, list) or not repos:
        return [*errors, "repos must be a non-empty list"]

    seen: set[str] = set()
    for i, entry in enumerate(repos):
        if not isinstance(entry, dict):
            errors.append(f"repos[{i}]: not an object")
            continue
        repo = entry.get("repo", "?")
        where = f"repos[{i}] ({repo})"
        errors.extend(check_entry(where, entry))
        key = str(repo).lower()
        if key in seen:
            errors.append(f"{where}: repo listed twice")
        seen.add(key)
    return errors


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        fleet = json.load(f)
    with open(argv[2], "rb") as f:
        profile = tomllib.load(f)
    errors = check(fleet)
    for error in errors:
        print(f"fleet.json: {error}", file=sys.stderr)
    if errors:
        return 1
    owner = profile.get("org", {}).get("github-owner") or "Avunu"
    notice = "::notice::" if os.environ.get("GITHUB_ACTIONS") else ""
    for entry in fleet["repos"]:
        if entry["repo"].split("/")[0].lower() != owner.lower():
            print(f"{notice}fleet.json: {entry['repo']} is outside {owner}, the profile's github-owner")
    shapes = {shape: sum(1 for r in fleet["repos"] if r.get("shape") == shape) for shape in SHAPES}
    private = [r["repo"] for r in fleet["repos"] if r.get("private")]
    print(
        f"fleet.json: {len(fleet['repos'])} repositories"
        f" ({', '.join(f'{n} {shape}' for shape, n in shapes.items() if n)}),"
        f" private: {', '.join(private) or 'none'}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
