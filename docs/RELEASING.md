# Releasing Scrapbot

Scrapbot releases are managed by release-please. Maintainers should keep merged commits on `main` in Conventional Commit format so release-please can decide the next SemVer version and generate release notes.

## Release Flow

1. Merge normal feature and fix PRs into `main`.
2. Let the `Release Please` workflow open or update its release PR.
3. Review the release PR. It should update `CHANGELOG.md`, `version.txt`, `odin-src/scrapbot/main.odin`, `src/root.zig`, `build.zig.zon`, and `.release-please-manifest.json`.
4. Merge the release PR when the release is ready.
5. Confirm the workflow created a GitHub release and uploaded both macOS archives:
   - `scrapbot-<version>-macos-arm64.tar.gz`
   - `scrapbot-<version>-macos-x86_64.tar.gz`

## Verification

After the release workflow finishes, download each archive and run:

```sh
tar -xzf scrapbot-<version>-macos-<arch>.tar.gz
./scrapbot-<version>-macos-<arch>/scrapbot version
```

For a fuller smoke test, initialize a temporary project and validate it:

```sh
./scrapbot-<version>-macos-<arch>/scrapbot init /tmp/scrapbot-release-smoke
./scrapbot-<version>-macos-<arch>/scrapbot check /tmp/scrapbot-release-smoke
```

## GitHub Settings

The repository must allow GitHub Actions to create pull requests. If release PRs are not appearing, check the repository's Actions settings first.

The release workflow uses `GITHUB_TOKEN`. Workflows triggered by release-please-created tags or releases should not be expected to run from separate `release` events; release artifacts are built from the Odin CLI in the same workflow after release-please reports that it created a release. macOS archives bundle the SDL3 runtime dylib beside the `scrapbot` binary.
