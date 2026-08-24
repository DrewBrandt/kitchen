# Project instructions

**I do not and will not ever give a fuck about backward compatibility. Just fix it and migrate.**
## Isolation, integration, and deployment

- Start every implementation task in its own Git worktree on a dedicated `codex/` branch. Do not implement directly on `main`.
- Preserve unrelated user or agent changes. Do not copy uncommitted work from another worktree unless its owner explicitly asks you to.
- New worktrees do not contain ignored dependency or build directories. Bootstrap each worktree before analysis or tests with `flutter pub get` at the repository root and `npm ci` in `functions/`. Use the lockfiles; do not copy `node_modules`, `.dart_tool`, or build output from another worktree.
- Run Flutter/Dart commands sequentially within a worktree. Concurrent first-run Flutter commands can contend on SDK initialization or package locks and appear to hang without output.
- On Windows, call `flutter.bat` and `dart.bat` explicitly. `where` may resolve the extensionless POSIX launchers before the `.bat` files, which can hang without output under PowerShell. If `dart.bat` still misbehaves, invoke the SDK executable under `<flutter-sdk>\bin\cache\dart-sdk\bin\dart.exe` directly.
- If the sandbox blocks dependency network access, rerun only the standard locked restore command with the required network approval. Do not replace the locked restore with copied dependencies or an unpinned install.
- In a restricted Windows workspace, Flutter may also need approval for analyze/test/build because it writes `D:\flutter\bin\cache\lockfile` outside the repository. A silent hang from `flutter.bat` can be this denied SDK-cache write; confirm with the direct SDK executable if needed, then rerun the original Flutter command with narrowly scoped approval.
- Firebase CLI commands require access to the authenticated user configuration at `C:\Users\<user>\.config\configstore\firebase-tools.json` and network access to Firebase/Google APIs. In a restricted workspace, use narrowly scoped approval for the exact read, deploy, or secret-metadata command; never work around it by copying authentication files into the repository.
- On Windows PowerShell, do not feed generated Firebase secrets with `[Console]::Out.Write(...) | firebase ... --data-file -`; direct console writes bypass the pipeline and can expose the value while Firebase receives an empty payload. Use a system temporary file passed via `--data-file`, create it outside the repository, never print its contents, and delete it in `finally` immediately after the CLI returns.
- When a task discovers another repeatable worktree-specific setup requirement or workaround, add it to this file in the same change so future agents do not have to rediscover it.
- Before integrating, update the feature branch from the latest committed `main`, resolve conflicts in the feature worktree, and rerun the feature tests plus the full regression suite. Verify that previously working behavior still works with the new feature.
- A completed change is not delivered until it is merged into `main`, pushed to GitHub, and deployed to Firebase. Deploy both Firebase Hosting and every changed Firebase backend surface (Functions, Firestore rules, and indexes as applicable); never deploy only GitHub or only Firebase.

### `main` merge lock

- The repository root on `main` uses `merging.lock` as a cooperative merge mutex. The file is intentionally untracked and must never be committed.
- Before changing, merging, committing, testing, pushing, or deploying from `main`, check for `merging.lock` in the main worktree.
- If it exists, do not modify or merge into `main`, do not delete the file, and do not assume it is stale. Recheck at semi-random intervals centered around one minute (for example 45-75 seconds) until it disappears.
- Acquire the lock by creating `merging.lock` only when it is absent. Include the owning branch/worktree, agent or task identifier, and an ISO-8601 UTC creation time so concurrent workers can identify the owner.
- After creating it, immediately confirm that the lock contents are yours before touching `main`. If acquisition raced with another worker, stop and resume waiting.
- While holding the lock, recheck that `main` has not acquired unexpected uncommitted changes. Merge the feature branch, run the full regression suite on the merged result, push `main` to GitHub, and deploy the complete application to Firebase.
- Remove only your own `merging.lock`, and remove it in a `finally`/cleanup path even if merge, testing, push, or deployment fails. The lock coordinates workers; it is not a substitute for reporting a failed delivery.
- After a successful merge, push, deployment, and post-merge verification, remove the completed feature worktree and delete its local feature branch.
