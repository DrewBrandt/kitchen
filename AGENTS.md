# Project instructions

**I do not and will not ever give a fuck about backward compatibility. Just fix it and migrate.**
## Isolation, integration, and deployment

- Start every implementation task in its own Git worktree on a dedicated `codex/` branch. Do not implement directly on `main`.
- Preserve unrelated user or agent changes. Do not copy uncommitted work from another worktree unless its owner explicitly asks you to.
- New worktrees do not contain ignored dependency or build directories. Bootstrap each worktree before analysis or tests with `npm ci` at the repository root. Use the lockfile; do not copy `node_modules` or build output from another worktree.
- API handler contract tests import Node built-ins. Keep `@types/node` as an explicit development dependency; its optional-peer presence in a local restore does not guarantee availability in the clean Pages build.
- When validating a feature worktree without environment files, also build with nonempty `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` placeholders. Otherwise Vite can remove the authenticated application as unreachable, leaving its bundle unverified. Use `https://example.supabase.co` and `build-validation-placeholder` for this build-only check; never deploy that output.
- If the sandbox blocks dependency network access, rerun only the standard locked restore command with the required network approval. Do not replace the locked restore with copied dependencies or an unpinned install.
- If Vitest fails before running tests with `EPERM` creating its temporary `client` directory under the user's Temp folder, rerun the same test command with narrowly scoped approval; do not change machine permissions or copy dependencies.
- Supabase CLI commands write telemetry state under `C:\Users\<user>\.supabase` even for read-only help and validation commands. In a restricted workspace, use narrowly scoped approval for the exact Supabase command; do not redirect or copy that user-level state into the repository.
- New worktrees do not inherit the ignored Supabase project link. Before a dry run,
  database test, or deployment there, run `npx.cmd supabase link --project-ref xaetuqdtnolzspfvqvja`;
  do not copy `supabase/.temp` from another worktree.
- In PowerShell scripts, invoke the Node package runner as `npx.cmd`. Calling `npx` with the call operator (`& npx ...`) can make the installed `npx.ps1` misparse the command as the unrelated `px` package.
- When a task discovers another repeatable worktree-specific setup requirement or workaround, add it to this file in the same change so future agents do not have to rediscover it.
- Receipt lifecycle validation uses `sh supabase/tests/run_receipt_isolated.sh` with Docker, cached `postgres:17`, and Python 3. On this Windows host, Docker is available through `wsl.exe -d Ubuntu -u root -- sh <WSL-worktree-path>/supabase/tests/run_receipt_isolated.sh` (scoped escalation required). This disposable harness never links Supabase: it uses synthetic auth rows with actual database roles, omits production-only historical repair DML in migration 009, and verifies the guard already installed by 018 instead of rerunning the deployment-only 019 text patch. It removes only its own container on exit.
- Before integrating, update the feature branch from the latest committed `main`, resolve conflicts in the feature worktree, and rerun the feature tests plus the full regression suite. Verify that previously working behavior still works with the new feature.
- A completed change is not delivered until it is merged into `main`, pushed to GitHub, and the GitHub Pages Actions deployment succeeds. Deploy changed Supabase migrations before or alongside application code that depends on them.

## Custom GPT maintenance

- To open the **My Pantry** GPT editor in ChatGPT, use the short UI path: click the pinned **My Pantry** item in the left sidebar, click **My Pantry** again at the upper-left of the main pane, then select **Edit GPT**. Do not take the longer **More → GPTs → My GPTs** route unless this shortcut is unavailable.

### `main` merge lock

- The repository root on `main` uses `merging.lock` as a cooperative merge mutex. The file is intentionally untracked and must never be committed.
- Before changing, merging, committing, testing, pushing, or deploying from `main`, check for `merging.lock` in the main worktree.
- If it exists, do not modify or merge into `main`, do not delete the file, and do not assume it is stale. Recheck at semi-random intervals centered around one minute (for example 45-75 seconds) until it disappears.
- Acquire the lock by creating `merging.lock` only when it is absent. Include the owning branch/worktree, agent or task identifier, and an ISO-8601 UTC creation time so concurrent workers can identify the owner.
- After creating it, immediately confirm that the lock contents are yours before touching `main`. If acquisition raced with another worker, stop and resume waiting.
- While holding the lock, recheck that `main` has not acquired unexpected uncommitted changes. Merge the feature branch, run the full regression suite on the merged result, push `main` to GitHub, and verify the GitHub Pages deployment.
- Remove only your own `merging.lock`, and remove it in a `finally`/cleanup path even if merge, testing, push, or deployment fails. The lock coordinates workers; it is not a substitute for reporting a failed delivery.
- After a successful merge, push, deployment, and post-merge verification, remove the completed feature worktree and delete its local feature branch.

- The disposable SQL harness accepts optional test filenames after the script path for focused validation (for example `recipe_piece_estimates.sql piece_cooking.sql`). On this host use `C:\Users\Snoopy\AppData\Local\Python\pythoncore-3.10-64\python.exe` when the Windows Store `python` alias is inaccessible.
- Keep shell harnesses LF-terminated (`*.sh text eol=lf` in `.gitattributes`); CRLF causes WSL `sh` to reject `set -eu`.
- Kitchen MCP prototype tests run with `npm test -- src/kitchen-mcp.test.ts src/inventory-api-parity.test.ts` after the normal locked restore. They use synthetic signed JWTs and in-process MCP transport, requiring no Supabase link or credentials. Do not infer a connected OAuth deployment from these tests; follow `docs/kitchen-mcp-prototype.md` before any live setup.
