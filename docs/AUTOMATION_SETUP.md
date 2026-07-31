# Automation Setup — Step by Step

> Click-by-click guide to switch the release automation on. You create the same thing three times
> (a GitHub App) and tick one checkbox.
>
> Reference for what all of this does: [`AUTOMATION.md`](./AUTOMATION.md).

Nothing here is destructive. Until the credentials exist the chain stays inert: `auto-tag.yml`
reports "Automatic tagging is inactive" and `mobile-release-artifacts.yml` reports a skipped
dispatch. You can merge the automation first and set it up afterwards.

## Part 1 — Three GitHub Apps

### App 1: the release tagger

**Step 1 — Create it**

Open <https://github.com/organizations/metadist/settings/apps/new> and fill in:

1. **GitHub App name**: `synaplan-release-tagger`
2. **Homepage URL**: `https://github.com/metadist/synaplan`
3. Scroll to **Webhook** and untick **Active**
4. Scroll to **Repository permissions** and set **Contents** to **Read and write**
5. At the bottom choose **Only on this account**
6. Click **Create GitHub App**

**Step 2 — Collect two values**

You are now on the app's page.

1. At the top it says **App ID** followed by a number. Copy that number.
2. Scroll down to **Private keys** and click **Generate a private key**. A `.pem` file downloads.

**Step 3 — Install it**

1. Click **Install App** in the left menu
2. Click **Install** next to `metadist`
3. Choose **Only select repositories**, pick `synaplan`, click **Install**

**Step 4 — Store the two values**

Go to <https://github.com/metadist/synaplan/settings/secrets/actions>.

1. **New repository secret**
   - Name: `MOBILE_TAG_APP_ID`
   - Secret: the number from step 2
2. **New repository secret**
   - Name: `MOBILE_TAG_APP_PRIVATE_KEY`
   - Secret: open the `.pem` in a text editor, select **everything** and paste it — including the
     `-----BEGIN ...-----` and `-----END ...-----` lines

Delete the `.pem` file from your disk afterwards. It is a private key.

### App 2: the dispatcher

Same four steps, with these values:

| | |
|---|---|
| Name | `synaplan-mobile-dispatch` |
| Permissions | **Contents: Read-only** |
| Install on | `synaplan-apps` |
| Secrets go into | `metadist/synaplan` |
| Secret names | `MOBILE_APPS_APP_ID`, `MOBILE_APPS_APP_PRIVATE_KEY` |

### App 3: the synchronizer

Same four steps again:

| | |
|---|---|
| Name | `synaplan-mobile-sync` |
| Permissions | **Contents: Read and write** *and* **Pull requests: Read and write** |
| Install on | `synaplan-apps` |
| Secrets go into | `metadist/synaplan-apps` |
| Secret names | `MOBILE_SYNC_APP_ID`, `MOBILE_SYNC_APP_PRIVATE_KEY` |

> Why three apps and not one: a tag created with the built-in `GITHUB_TOKEN` does not start any
> workflow, so the tagger needs its own credentials. The write scope for the app repository is kept
> out of the public repository, which is why the dispatcher is read-only and separate.

## Part 2 — One checkbox

Open <https://github.com/metadist/synaplan-apps/settings>, scroll to **Pull Requests** and tick
**Allow auto-merge**.

Without it the synchronization pull request opens but never merges itself.

## What works now

A merge into `synaplan` `main` is tagged, the pin in this repository is updated, and the pull
request merges itself once Mobile CI is green.

## Part 3 — Publishing (needs your own credentials)

Everything above is mechanical. Actually publishing needs values only you have: the self-hosted
Capgo deployment, the Apple signing material and the Google Play service account.

Create the environments `canary`, `production` and `store-qa` under
<https://github.com/metadist/synaplan-apps/settings/environments> and fill them with the names
listed in [`AUTOMATION.md`](./AUTOMATION.md#3-environments-in-synaplan-apps).

Our own deployment splits across three hostnames — the console you log into is not the API:

| Purpose | Host |
|---------|------|
| Console (browser only) | `capgo.<domain>` |
| Plugin API — `updates`, `stats`, `channel_self`, `statistics` | `api.capgo.<domain>` |
| Supabase/Kong, the CLI's `--supa-host` | `sb.capgo.<domain>` |

Four things are easy to get wrong there:

- `CAPGO_CHANNEL` must be spelled exactly like the environment it sits in (`canary` or
  `production`). `ota.yml` refuses a mismatch.
- `CAPGO_STATS_URL` and `CAPGO_STATS_API_URL` are different endpoints. The first is `/stats`, where
  the app reports to; the second is `/statistics`, where the health check reads from.
- `CAPGO_API_KEY` needs **both** scopes in practice: uploading is a write operation, while
  `/statistics` requires a read-scoped key. A pure upload key makes the health check fail.
- The upload and statistics endpoints must answer from the public internet. The workflows run on
  GitHub-hosted machines, so an endpoint reachable only inside a private network will fail there.

Do not add required reviewers to `canary` or `production` — that is exactly the manual approval
this automation removes. `store-qa` may keep reviewers: the build still runs automatically, only
the store upload waits for a human.
