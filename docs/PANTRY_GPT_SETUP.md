# Set up the private Pantry GPT

This setup gives every new conversation opened with the private GPT live access
to the Supabase pantry. A knowledge-file upload by itself cannot authenticate.

## 1. Create the GPT

In ChatGPT, open **Explore GPTs**, choose **Create**, and configure:

- Name: `Drew's Pantry`
- Visibility: **Only me**
- Description: `Private pantry, nutrition, recipe, and weekly meal-planning assistant.`
- Enable Web Search if you want it to research recipes and current label data.

Paste the complete contents of `docs/PANTRY_GPT_INSTRUCTIONS.md` into the GPT's
Instructions field. You may also upload `docs/API.md` as Knowledge for additional
API examples, but do not upload or paste the bearer token into Knowledge,
Instructions, a conversation, or GitHub.

Keep the Instructions file at or below the Custom GPT editor's 8,000-character
limit. The backend test suite enforces this limit.

Suggested conversation starters:

- `Plan next week using what I have, while avoiding meals I ate recently.`
- `I just got groceries. Help me reconcile the list and upload it.`
- `Find three dinners I can make with one small store run.`
- `I ate this today; log it and tell me how it compares with my targets.`

## 2. Add the Pantry Action

In the GPT editor, open **Actions** and create a new Action.

1. Paste the complete contents of `docs/pantry-gpt-openapi.yaml` into Schema.
2. Set Authentication to **API key**.
3. Select **Bearer** authentication.
4. From this repository in PowerShell, run:

   ```powershell
   .\tools\copy_api_token.ps1
   ```

5. Paste the clipboard value into the Action authentication secret field.
6. Do not paste the token into the schema itself.

The bearer token is stored as a Supabase Edge Function secret and locally with
Windows DPAPI. It is copied without being
printed. Clipboard history can retain copied secrets, so clear the clipboard
after the GPT is saved:

```powershell
Set-Clipboard -Value ''
```

## 3. Test before relying on writes

In Preview, ask:

1. `Read my pantry and tell me how many eggs I have.`
2. `Search my saved outside foods for Chick-fil-A. Do not create anything.`
3. `Show my current meal plan and grocery list.`
4. `Propose adding Coffee filters as a manual grocery item, but do not add it.`

The first three should call read Actions. The fourth should stop before the write.
Then explicitly confirm the test write, verify it appears in the app, and remove
it from the app if it was only a test.

If an Action receives `401 Unauthorized`, re-enter the bearer token in the GPT
Action authentication settings. A `422` response means the API rejected invalid
or ambiguous structured data without applying a partial write.

## Ordinary fresh chats

A normal ChatGPT conversation that is not opened with this custom GPT will not
inherit its private Action. It can use an uploaded copy of the instructions as a
guide, but it cannot read or write live pantry data securely. Open a new chat
with **Drew's Pantry** whenever live access is needed.

## Applying later API or instruction updates

Repository edits do not update the deployed Edge Function or private GPT
automatically. After changing the API or GPT behavior:

1. Apply migrations with `npm run db:push -- --agent no`.
2. Deploy with `npx supabase functions deploy pantry-api --no-verify-jwt --project-ref xaetuqdtnolzspfvqvja --agent no`.
3. Replace the GPT Instructions with the complete current contents of
   `docs/PANTRY_GPT_INSTRUCTIONS.md`.
4. Replace the Action schema with the complete current contents of
   `docs/pantry-gpt-openapi.yaml` and save the GPT.
5. Repeat the read-only Preview tests above.
