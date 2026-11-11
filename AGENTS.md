# Guidelines for Agents

## Release Management
Releases are automated via GitHub Actions ([.github/workflows/release.yml](.github/workflows/release.yml)). When changes with a new `SETUP_VERSION` are merged into `main`, the workflow automatically detects if the tag `vX.Y.Z` exists, extracts the release notes from `CHANGELOG.md`, and creates the GitHub release.

### Why releases are critical:
The launcher script (`$PREFIX/bin/copilot`) queries `https://api.github.com/repos/cafeteru/copilot-termux/releases/latest` to check for updates.
If a release is not published in GitHub:
- Existing users will not receive the startup update prompt (`¿Deseas actualizar ahora? [s/N]`).
- Auto-updates via `copilot-termux-update` will not detect new repository versions.

### Workflow for any new version:
1. Update `SETUP_VERSION` in `setup.sh`.
2. Document changes under a new version heading in `CHANGELOG.md` and update `README.md` if applicable.
3. Verify with `bash setup.sh self-test`.
4. Open a pull request, review, and merge to `main`.
5. The `Auto Release` GitHub Action will automatically publish the release. If it fails or is delayed, create it manually:
   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z" --notes "<Release Notes>"
   ```
