# odoo-standards-profile

Avunu's Odoo standards profile for [odoo-nix](https://github.com/Avunu/odoo-nix).

odoo-nix can manage the tooling of an Odoo repository: OCA's lint and format configs with the
tools locked per Odoo series, pre-commit hooks, editor settings, the manifest policy,
conventional commits, the release flow, CI callers, Dependabot, repository policy, READMEs and
addon icons. A repository opts in with a `[tool.odoo-nix]` table, and a **profile** decides
which of those modules are on and with which values. odoo-nix ships two vendor-neutral
built-in profiles, `minimal` and `recommended`. This repository is Avunu's org profile, layered
on top of the frozen `recommended@2.3` snapshot. It holds Avunu's organisation values
(publisher, contact, licence, URLs, the addon manifest policy) and every switch the Avunu
fleet relies on.

It is the Odoo counterpart of
[frappe-standards-profile](https://github.com/Avunu/frappe-standards-profile), which does the
same for Frappe apps and frappe-nix.

odoo-nix knows two repository shapes, and the profile serves both:

- **addons**: a repository of addons at its root, with OCB as a `flake = false` input, the
  series in `.odoo-series` and odoo-nix's uv project in `nix/` (addons mode), such as the
  `Avunu/*-addons` repositories;
- **project**: a deployment, with OCB as the `odoo/` submodule, OCA repositories as `modules/*`
  submodules and its own addons in `custom/`.

The profile format, the modules and the merge order are documented in odoo-nix's
[standards docs](https://github.com/Avunu/odoo-nix/tree/main/docs/standards)
(`profiles.md`, `modules.md`).

## What is here

| Path | What it is |
| --- | --- |
| [`profile.toml`](profile.toml) | The profile. It extends odoo-nix's frozen `recommended@2.3` snapshot and sets Avunu's values and every switch the fleet relies on, so an odoo-nix release that changes `recommended` can't move an Avunu repository. |
| [`fleet.json`](fleet.json) | The Avunu fleet: the public addon repositories that `odoo-nix repo apply\|audit\|rollout\|targets --all --fleet fleet.json` iterate, each with its shape, its `branches` (`["develop", "18.0"]`: the integration branch first, then the series branch), whether it is private and its documentation URL (the repository homepage `repo apply` sets; not published yet, see [Before the first release](#before-the-first-release)). Client deployments are never listed here. |
| [`resolved.project.snapshot.json`](resolved.project.snapshot.json) | The resolved configuration (`odoo-nix profile show --format json`) of odoo-nix's `standards-project` fixture under this profile. CI compares against it, so any change to a resolved value, from this repository or from odoo-nix, is a reviewed diff. Against the newest allowed odoo-nix release, CI accepts options that release adds beyond the pinned one, and fails on any value that moves or any new module that is on. |
| `resolved.addons.snapshot.json` | The same for the `standards-addons` fixture: odoo-nix derives part of the configuration from the shape, so each shape has its own snapshot. Not committed yet (see [Before the first release](#before-the-first-release)). |
| [`scripts/check.sh`](scripts/check.sh) | The checks CI runs: `odoo-nix profile validate`; for each fixture, the snapshot comparison (with [`scripts/compare_snapshot.py`](scripts/compare_snapshot.py) for the newest release) and an offline `odoo-nix sync --write` then `--check` with this profile; then `fleet.json`, against odoo-nix's fleet schema and the rules in [`scripts/check_fleet.py`](scripts/check_fleet.py). |
| [`flake.nix`](flake.nix) | Pins the odoo-nix the checks run against (the `v2.3.0` tag). Dependabot moves it within the major. `flake.lock` is added once that tag exists: until then the flake cannot be locked. |
| [`repo-policy/`](repo-policy) | This repository's own settings and rulesets, for `odoo-nix repo apply --policy-dir repo-policy Avunu/odoo-standards-profile` (`--dry-run` first shows the changes). |
| `assets/addon-icon.png` | The Avunu addon icon: `odoo-nix check icons --fix` runs `oca-gen-addon-icon --src-icon=<profile>/assets/addon-icon.png` for each addon without a `static/description/icon.png`. Not added yet (see [Before the first release](#before-the-first-release)). |
| `templates/` | Template overrides that odoo-nix reads from the profile directory (`<profile>/templates/`), so they travel with each profile release. None yet: every managed file comes from odoo-nix's own templates. Only overridable templates and `[[extra-files]]` templates may live there, which is why the icon is under `assets/`. |

## What it sets on top of `recommended`

| Module or table | `recommended@2.3` | This profile |
| --- | --- | --- |
| `[org]` | empty | Avunu LLC, `mail@avu.nu`, licence `AGPL-3`, owner `Avunu`, `https://docs.avunu.net/{repo_name}/`, `https://docs.avunu.net/odoo-nix/docs/standards/` |
| `addon-manifest` | no author, OCA's licences, no website | author `Avunu LLC`, licences `AGPL-3` and `LGPL-3`, website `https://github.com/{repo}` |
| `ide` | off | on: VS Code with Odoo LS, ruff and prettier; Pylance and ty off |
| `commits` | off | on: conventional commits scoped by addon, plus `ci`, `deps`, `docs`, `main`, `release`, `tests`; no stacked pull requests |
| `releases` | off | on, `develop+series` (below) |
| `packaging` | off | on: a whool `pyproject.toml` per addon |
| `dependabot` | auto-merge by odoo-nix's decision table | auto-merge every Dependabot PR once its checks pass (`all`), and keep them up to date (`update-branches`) |
| `ci` | `ubuntu-latest`, no App | `["self-hosted", "nixos"]`; the "Avunu CI" App: variable `AVUNU_CI_APP_ID` (its client ID), secret `AVUNU_CI_PRIVATE_KEY` |
| `repo-policy` | off | on, no required approvals |
| `readme` | off | on: a `README.md` per addon, no generated addons table in the root README |
| `icons` | off | on: square, at least 128 px, at most 100 KB |
| `[[retire]]` | none | `.github/workflows/mirror.yml`, the addon repositories' stopgap release flow |

Everything else (the dev shell, editorconfig, ruff and pylint-odoo with OCA's per-series rules,
js-xml, tests with coverage, workflow, shell and Nix lint, hygiene) is `recommended`'s, frozen
with it. `resolved.project.snapshot.json` lists every resolved value.

## How a repository uses it

The `[tool.odoo-nix]` table goes in the file odoo-nix's own uv project lives in:

- an **addon repository** (addons mode): `nix/pyproject.toml`. Addon repositories have no
  root `pyproject.toml`;
- a **project**: the root `pyproject.toml`.

### An addon repository

In `nix/pyproject.toml`:

```toml
[tool.odoo-nix]
schema = 1
profile = "github:Avunu/odoo-standards-profile/v1"
```

odoo-nix works out the shape, the series (from `.odoo-series`) and the addons; the profile
supplies everything else.

**Release flow (`develop+series`).** Pull requests go to `develop`. After each merge,
`odoo-release.yml` works out each changed addon's manifest version bump from the conventional
commits since the series branch (`!` → major, `feat` → minor, `fix`/`perf` → patch, other types
none), commits `chore(release): bump <addons>` to `develop` with the CI App's token and, once
the required checks pass on that commit, fast-forwards the series branch named in
`.odoo-series` (`18.0`), the branch other repositories install from. The series branch is
never pushed to by hand. The first sync deletes `.github/workflows/mirror.yml`, which this
flow replaces.

A repository that differs from the fleet sets the difference in its own table; tables merge
key by key over the profile, for example an addon kept out of the test run:

```toml
[[tool.odoo-nix.untested]]
addon = "my_demo_data"
reason = "seeds an empty database"
```

### A client project with overrides

A private deployment, such as a client project, uses the same profile in its root
`pyproject.toml`, with its own organisation values, and turns off what doesn't fit a single
private repository:

```toml
[tool.odoo-nix]
schema = 1
profile = "github:Avunu/odoo-standards-profile/v1"
integration-branch = "master"

[tool.odoo-nix.org]
publisher = "Example Client LLC"
copyright-holder = "Example Client LLC"
email = ""
github-owner = "Example-Client"
license = "LGPL-3"                               # new addons' licence: one of licenses-allowed
docs-url = ""
dev-docs-url = ""

[tool.odoo-nix.addon-manifest]
author = "Example Client LLC"
licenses-allowed = ["LGPL-3"]
website = ""

[tool.odoo-nix.ci]
runs-on = ["ubuntu-latest"]
github-app = { app-id = "", private-key = "" }   # tables deep-merge: blank the names to turn the App off

[tool.odoo-nix.dependabot]
auto-merge = false

[tool.odoo-nix.releases]
enable = false                                   # a deployment has no series branch to release to

[tool.odoo-nix.repo-policy]
enable = false                                   # rulesets need a public repository or a paid plan

[tool.odoo-nix.packaging]
enable = false                                   # whool packaging is for addon repositories

[[tool.odoo-nix.untested]]
addon = "example_demo_data"
reason = "seeds an empty database"
```

Every key above is in odoo-nix's schema; `odoo-nix profile show --explain` in the checkout
says which layer set each value. Such repositories are not listed in `fleet.json`, which is
public; their owners roll new profile releases out by hand (below).

### Taking a profile release

`odoo-init --sync` adds the profile to the repository's `flake.nix` as the input
`standards-profile` (`flake = false`) and locks it, so every commit renders from exactly one
revision of this repository. Dependabot never moves that input, because a profile change can
rewrite workflow files. A repository takes a new profile release with

```sh
nix flake update standards-profile && nix run --no-pure-eval .#odoo-init -- --sync
```

or, for the whole fleet, `odoo-nix repo rollout --profile-to latest --all --fleet fleet.json`.

## Releases

Releases are cut by release-please from conventional commits on `main`: tags `vX.Y.Z`, and a
moving branch `v1` that the release workflow fast-forwards to each new tag. Repositories lock
`v1`, so it only ever points at a release. The first release is 1.0.0.

Versioning follows odoo-nix's rules for org profiles:

- **MAJOR**: a change that makes `odoo-nix profile validate` or a repository's
  `odoo-init --check` fail without an edit in that repository (a module turned on that needs
  configuration, a stricter value). Repositories move by editing `/v1` to `/v2`.
- **MINOR**: modules turned on or parameters changed that `--sync` applies by itself.
- **PATCH**: organisation value fixes (a URL, an e-mail address).

`requires-odoo-nix` declares the odoo-nix versions the profile is written for; sync refuses a
profile whose range excludes the running odoo-nix.

## Changing the profile

1. Edit `profile.toml` (or `fleet.json`) on a branch.
2. Run the checks, inside `nix develop` or with Nix available:

   ```sh
   scripts/check.sh            # what CI runs
   scripts/check.sh --update   # rewrite the resolved.*.snapshot.json after an intended change
   ```

   `ODOO_NIX` (a command, split on spaces) and `ODOO_NIX_SRC` (a source tree with
   `tests/fixtures/`) point the checks at another odoo-nix, for example a local checkout.
   Until the pinned release exists, that is the only way to run them, for example with an
   odoo-nix checkout at `../odoo-nix` and python-devops-nix's standards core at
   `../python-devops-nix`:

   ```sh
   nix build ../odoo-nix#odoo-nix --override-input python-devops-nix path:../python-devops-nix \
     --out-link /tmp/odoo-nix-dev
   ODOO_NIX=/tmp/odoo-nix-dev/bin/odoo-nix ODOO_NIX_SRC=../odoo-nix scripts/check.sh
   ```

   An odoo-nix-tools older than 2.3.0 is such a development build: the checks then read
   `profile.toml` without its `requires-odoo-nix` line, with a warning. That workaround
   exists only until odoo-nix 2.3.0 is tagged and locked, and is removed then (see
   [Before the first release](#before-the-first-release), item 1). One that can't read
   `[tool.odoo-nix]` from `nix/pyproject.toml` yet skips the addons fixture with a warning,
   as long as no `resolved.addons.snapshot.json` is committed; `ODOO_NIX_SKIP_ADDONS=1`
   skips it on purpose.

   To try the profile on a real repository before publishing, run
   `nix run --no-pure-eval .#odoo-init -- --sync --profile-path ../odoo-standards-profile`
   in that repository's checkout (and don't commit the result).
3. Open a PR with a conventional-commit title (`feat:`, `fix:`, `chore:` …). The `validate`
   check must pass.

## Before the first release

This repository is a draft until these are done, in this order:

1. **odoo-nix 2.3.0 is tagged.** It is the first release with the standards engine and the
   frozen `recommended@2.3`. If the release is another minor, move `flake.nix`'s pin and
   `profile.toml`'s `extends` and `requires-odoo-nix` to it. Then run `nix flake lock`,
   `scripts/check.sh --update`, and commit `flake.lock` and the snapshots. In the same
   change, delete `scripts/check.sh`'s development-build branch (`first_release` and the
   copy of `profile.toml` without its `requires-odoo-nix` line) and the paragraph about it
   under [Changing the profile](#changing-the-profile): against a locked release in range it
   never runs, and left in place it could only hide an `ODOO_NIX` that points at the wrong
   build. From then on an engine outside `requires-odoo-nix` fails `profile validate`.
2. **The addons snapshot.** Once odoo-nix-tools reads `[tool.odoo-nix]` from
   `nix/pyproject.toml` (the standards core's per-checkout config file, change request CR1),
   `scripts/check.sh --update` writes `resolved.addons.snapshot.json`; commit it, and the
   addons fixture is required from then on.
3. **The CI App's numeric id.** Set `release-bypass = "integration:<id>"` in `profile.toml`'s
   `[repo-policy]`, with the "Avunu CI" App's numeric App id from its settings page (not the
   client ID in `AVUNU_CI_APP_ID`). Without it the release ruleset doesn't let the App push
   the bump commit or fast-forward the series branch, and `odoo-nix repo doctor` reports it
   missing.
4. **The addon icon.** Add the Avunu addon icon as `assets/addon-icon.png` (square, at least
   128 px, at most 100 KB). Until then `odoo-nix check icons` still checks every addon's
   icon, but `check icons --fix` refuses (exit 2).
5. **The GitHub repository.** Create `Avunu/odoo-standards-profile` (public, so consumers
   need no fetch token), push `main`, and have an admin run
   `odoo-nix repo apply --policy-dir repo-policy Avunu/odoo-standards-profile` (with
   `--dry-run` first to see the changes). That
   requires a PR and the `validate` check on `main`, lets only GitHub Actions move `v*`
   branches, and protects `v*` tags. Until then, the release workflow needs the setting
   "Allow GitHub Actions to create and approve pull requests" (Settings → Actions → General).
6. **The self-hosted runners.** Give `Avunu/odoo-standards-profile` access to the org's
   self-hosted `["self-hosted", "nixos"]` runner group (Organization settings → Actions →
   Runner groups). `dependabot-auto-merge.yml`'s python-devops-nix reusable workflows run
   there for every pull request that is not from a fork, Dependabot's included, and on push
   and schedule; without access those jobs queue and never start.
7. **The documentation pages.** Publish `https://docs.avunu.net/<repo>/` for each repository
   in `fleet.json`, and the standards page `profile.toml`'s `[org] dev-docs-url` names
   (`https://docs.avunu.net/odoo-nix/docs/standards/`). All of them return 404 today. Each
   fleet entry's `documentation` becomes that repository's homepage through
   `odoo-nix repo apply`, so run no `repo apply --all --fleet fleet.json` before they are
   live, or the fleet's public repositories get a broken homepage.
8. **The `v1` branch.** Merge the first release PR: release-please tags `v1.0.0` and the
   release workflow creates `v1` at it. Only then can repositories select
   `github:Avunu/odoo-standards-profile/v1`.
9. **The fleet audit** (optional, after the tag): add the caller below.

`Avunu/odoo-studio` and `Avunu/odoo-carbon-ui` join `fleet.json` once they are public.

Neither odoo-nix nor the standards core has an offline command that only validates a fleet
file yet, so `scripts/check.sh` validates `fleet.json` through `odoo-nix repo targets` with
the network transports turned off, and reads its exit code (3) and its `git clone` error as
the pass. If a release changes either, the check fails rather than passing. Switch it to
the offline command once one ships.

### The fleet audit

The weekly scorecard across the fleet runs from this repository through odoo-nix's reusable
`fleet-audit.yml`, with a read-only fine-grained token over the fleet's repositories
(Administration, Contents, Actions and Variables read, and Secrets read for `repo doctor`'s
rows) stored as the secret `ODOO_NIX_AUDIT_TOKEN`; without it the rows that need it are
`unknown`. The caller, `.github/workflows/fleet-audit.yml`, is added in the
same commit that pins the real odoo-nix tag, since a placeholder SHA fails zizmor's
impostor-commit check. Replace `<sha>` with that tag's commit and `v2.3.0` with the tag, and
check the inputs against that release's `fleet-audit.yml`:

```yaml
name: fleet-audit

# The weekly scorecard of the Avunu Odoo fleet (fleet.json): odoo-nix's reusable
# fleet-audit.yml runs `odoo-nix repo audit --all --fleet fleet.json` and keeps the scorecard
# in an issue of this repository. The secret ODOO_NIX_AUDIT_TOKEN is a read-only fine-grained
# token over the fleet's repositories (Administration, Contents, Actions, Variables and
# Secrets read); without it the rows that need it are `unknown`. Dependabot does not move the pin: it moves with
# flake.nix, by hand.

on:
  schedule:
    - cron: "0 7 * * 1"
  workflow_dispatch:

permissions: {}

concurrency:
  group: fleet-audit
  cancel-in-progress: false

jobs:
  audit:
    permissions:
      contents: read # the checkout, with the fleet list
      issues: write # the scorecard issue in this repository
    uses: Avunu/odoo-nix/.github/workflows/fleet-audit.yml@<sha> # v2.3.0
    with:
      fleet: fleet.json
      issue-repo: ${{ github.repository }}
    secrets:
      AUDIT_TOKEN: ${{ secrets.ODOO_NIX_AUDIT_TOKEN }}
```

## Another organisation

Copy `profile.toml`, change `name`, `description`, `[org]`, `[addon-manifest]` and the
switches, publish it as `github:<owner>/<repo>` with the same release flow, and point your
repositories at it. A team that wants no profile repository can use
`profile = "recommended"` with a few `[tool.odoo-nix.org]` values in each repository, or keep
a profile inside the repository itself (`profile = "./.standards-profile"`).

## Licence

[MIT](LICENSE)
