# Conventions: branches, pull requests, releases

The same way of working for every Jonc. Studios project. It is GitHub Flow with version tags: one long-lived branch (`main`), short branches for the work, and a tag whenever something goes live.

## Branches

`main` is always deployable and always matches what runs on staging. Nobody commits to it directly. All work happens in a short-lived branch from `main`:

| Prefix | For | Example |
|---|---|---|
| `feature/` | new functionality | `feature/send-screen-envelopes` |
| `fix/` | bug fixes | `fix/claim-expiry` |
| `chore/` | maintenance, dependencies, CI, docs, refactors | `chore/update-vite` |

Use lowercase and hyphens, and describe the result rather than the ticket. Keep branches small: a few days of work at most. Delete them after merging (GitHub can do this automatically under Settings → General → "Automatically delete head branches").

## Commits

Write short messages in the imperative: "Add claim expiry to send screen", not "added stuff". Prefixes such as `feat:` and `fix:` are welcome but not required. The release notes come from the pull request titles, not from the commits.

## Pull requests

1. Push the branch and open a PR to `main`. The PR gets a label from its prefix automatically (`feature`, `fix`, `chore`).
2. The **title** becomes the line in the release notes, so write it for a reader: "Send screen: envelopes stack with a counter".
3. CI must be green. Look at the change on a screenshot or locally when it touches the UI.
4. **Squash and merge.** One PR is one commit on `main`, so the history stays readable and every commit on `main` can be reverted on its own.
5. After the merge, staging updates on its own. Check it there.

## Releases

Versions follow [Semantic Versioning](https://semver.org): `vMAJOR.MINOR.PATCH`.

- **PATCH** (`v1.4.1`): fixes only.
- **MINOR** (`v1.5.0`): new features, backwards compatible.
- **MAJOR** (`v2.0.0`): breaking changes, including anything that needs manual work on the server (new `.env` values, a data migration).

Go live by tagging the commit on `main` that is on staging and approved:

```bash
git switch main && git pull
git tag v1.5.0
git push origin v1.5.0
```

The pipeline then gives that exact staging image the version tag, deploys it to production with a backup first, and publishes a GitHub Release with the notes grouped by label. Release candidates (`v1.5.0-rc.1`) follow the same path and are marked as pre-releases.

## Hotfix

Usually a hotfix is just a `fix/` branch → PR → merge → tag a patch version.

If `main` already holds work that may not go live yet, branch from the release tag instead:

```bash
git switch -c fix/urgent-thing v1.5.0
# fix, commit, push, and let CI run on the PR without merging
git tag v1.5.1 && git push origin v1.5.1   # tag the fix commit itself
```

Then merge the PR into `main` so the fix is not lost. The pipeline builds the image for that commit, because staging never had it, and deploys it to production.

## Rolling back

- **Automatically:** if the new version does not pass its health check, the deploy puts the previous image back and the run fails.
- **By hand:** in GitHub, open Actions → the release run of the version you want back → "Re-run all jobs". That version gets deployed again.
- Database changes only move forward (new tables and columns). An older version runs fine on a newer schema. If a release did change data, restore the backup from `<deploy-dir>/backups/` before rolling back.

## Protecting `main`

Settings → Rules → Rulesets → new branch ruleset for `main`:

- require a pull request before merging;
- require status checks to pass (pick the CI jobs);
- block force pushes;
- allow only squash merging (Settings → General → Pull Requests).

Rules on **private** repositories need GitHub Pro (or Team). On the Free plan the rules can't be enforced, but the flow above works the same. It just relies on discipline.
