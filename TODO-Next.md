# Next

Follow-up work after the v1 rename. Independent of that branch, which is already
large.

## 1. Publishing Stays Release-Driven

Decided: keep publishing on tag push and manual dispatch until 1.0 is
formalized. No change to `publish.yml`. The container image keeps publishing
from `main` on its own cadence as `:latest`.

Revisit at 1.0, and note two things that will matter then:

- **nuget.org and GitHub Packages both reject a version that already exists,
  permanently.** Any "publish on push" scheme has to publish only when
  `ModuleVersion` changes, or it fails on the second push.
- **The first nuget.org push claims `SubZeroDev.PSGenerator` forever.** It can be
  deprecated but never renamed, so confirm the public name before publishing.

Also worth deciding then: whether the image should carry `:1.0.0` alongside
`:latest`, so an image can be matched to a package version. The image now
publishes `:latest` only.

## 2. Gaps Found During the Rename

Small, concrete, and each one is a thing that can silently rot.

- **No status check is required on `main`.** The `Main` ruleset now protects the
  branch — a pull request is required, force pushes and deletion are blocked,
  admins are included, review threads must be resolved, and merges are squash or
  rebase only. What it does not have is a `required_status_checks` rule, and
  neither does classic protection, so a red PowerShell quality, documentation,
  Pester, or docs run still does not block a merge. The deploy-path coverage
  added in #61 exists specifically to fail before merge rather than after;
  without required checks it only reports.

  Add these ten contexts, exactly as CI reports them. A context that does not
  match a reported check name never becomes required, and fails silently rather
  than loudly:

  ```text
  Build and publish image
  Container end-to-end
  Documentation links and terminology
  Pester (ubuntu-latest)
  Pester (windows-latest)
  PowerShell 7.4 baseline (ubuntu-latest)
  PowerShell 7.4 baseline (windows-latest)
  PowerShell NuGet package
  PowerShell quality
  Verify documentation / Verify Documentation Build
  ```

  Only the reusable documentation workflow carries a `caller / job` prefix; the
  rest report their job name alone.

  Do not require `Deploy documentation`: it is skipped on pull requests by
  design, because its job is gated on `github.event_name == 'push'`.
- **Head branches are not deleted on merge.** Nine stale branches accumulated
  before being cleaned up, all of them pointers into already-merged history. The
  two most recent behaved differently — `#62`'s branch went automatically while
  `feature/replace-docs-workflow` stayed — so the setting is not on for every
  merge path. Turn on *Automatically delete head branches* in repository
  settings and the list stops growing on its own.
- **A generated command can shadow an existing one.** Since the inference naming
  fix, `convertto-json.ps1` produces `ConvertTo-Json`, which shadows the built-in
  once the module is imported. Documented as a note in the script inference
  guide, but inference could detect the collision and warn, the same way it warns
  about source commands without runtime mappings.
- **`.gitignore` does not cover `bin/` and `obj/`.** The BuildAgent fixture's
  `.csproj` files produce build output that shows up as untracked noise whenever
  anything builds them. Those directories are currently empty, so it is quiet
  right now, and it will come back.

## 3. Still Open on the v1 Roadmap

Not re-planned here, just so it is not forgotten. `TODO.md` still has:

- **§3 Docker-BuildAgent compatibility** — 11 of 13 items unchecked, and this is
  the largest remaining piece of engineering. Includes the maintenance-script
  classification that would keep repo tooling out of a public command surface.
- **§4 Inspector hardening** — all 6 unchecked, starting with the warn-versus-fail
  malformed-input policy.
- **§5** — device and GPU mappings on runners that expose the hardware.
- **Three documentation-toolchain follow-ups** — the `docs-build.ps1` prune
  manifest, whether `docs/Dockerfile` and `.dockerignore` should stay, and
  whether the `docs.yml` caller is still worth having. All upstream-shaped and
  lower priority since the 404 fix removed the reason the prune manifest existed.

## 4. Converge the Docs Workflows on the Portable Shape

`planning/Install-DocsSystem.ps1` installs a single `docs-ci.yml` into other
projects, carrying three jobs: the gate, the site build, and deploy. This
repository still uses the older split — `docs.yml` calling `docs-ci.yml` and
`docs-deploy.yml`, with the gate living as the `documentation` job inside
`test.yml`.

Both arrangements work, and nothing is broken. But the reference and the thing it
is meant to reproduce should not drift apart, and four files doing what one file
does is harder to explain than it is worth.

- Collapse `docs.yml`, `docs-ci.yml`, `docs-deploy.yml`, and the `documentation`
  job in `test.yml` into one `docs-ci.yml` matching the installed shape.
- The gate keeps the check name **Documentation links and terminology**, so that
  required check keeps matching. **`Verify documentation` and `Deploy
  documentation` do not** — they become `Verify Documentation Build` and `Build
  and Deploy Documentation`. Update branch protection in the same pull request,
  or the new names are simply not required and a red run stops blocking.
- Invoke the gate with `-TreatWarningsAsErrors` to preserve today's behaviour,
  where any finding fails the build.

Separate pull request. Worth doing once the docs image carries the payload and
the installer has been used against a real project at least once, so this repo
converges on something already proven rather than on a guess.

## Sequencing

Dropping Docusaurus versioning is done, so the snapshot no longer has to be
re-cut on every documentation change.

Of what remains, the two repository settings in section 2 are the highest
leverage and cost nothing: without required status checks, none of the gates
block a merge. After that, the `index.md` drift check, since it closes a gap
that currently depends on someone remembering. Publishing waits for 1.0.
