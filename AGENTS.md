# Guidelines for Agents

## Release Management
Always create a GitHub release (`gh release create vX.Y.Z`) after merging a version bump, feature, or fix into `main`.

### Why it is critical:
The launcher script (`$PREFIX/bin/copilot`) queries `https://api.github.com/repos/cafeteru/copilot-termux-setup/releases/latest` to check for updates.
If a release is not published in GitHub:
- Existing users will not receive the startup update prompt (`¿Deseas actualizar ahora? [s/N]`).
- Auto-updates via `copilot-termux-update` will not detect new setup repository versions.

### Steps for any new version:
1. Update `SETUP_VERSION` in `setup.sh`.
2. Document changes in `CHANGELOG.md` and `README.md`.
3. Verify with `bash setup.sh self-test`.
4. Open a pull request, review, and merge to `main`.
5. Immediately create the corresponding GitHub release:
   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z - <Summary>" --notes "<Release Notes>"
   ```
