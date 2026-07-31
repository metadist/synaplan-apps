# Store Setup

How to make `store-rc.yml` able to sign and upload a release candidate. Everything here is a
one-time setup per store. `docs/SECRETS.md` states the policy for handling this material;
this document is the click-by-click path to obtaining it.

The store credentials live in the **`store-qa`** environment, not in repository secrets, because
the workflow selects that environment and only its values are visible to the job.

## Shipping one store before the other

`STORE_PLATFORMS` in the `store-qa` environment decides which stores a release candidate is built
for. Set it to `ios` while Android is not published yet, and to `ios,android` once both are ready.
A manual run can override it through the `platforms` input.

This matters because Android is built before iOS in the job. Without the selection, a missing
Android keystore would fail the run before the iOS build is even reached.

## Prerequisite: the OTA configuration

The build refuses to start unless these variables exist in `store-qa`. They are compiled into the
binary and tell the installed app where to fetch updates and how to verify them. Copy the values
from the `production` environment:

```bash
for v in CAPGO_UPDATE_URL CAPGO_CHANNEL_URL CAPGO_STATS_URL; do
  val=$(gh api "repos/metadist/synaplan-apps/environments/production/variables/$v" -q .value)
  gh variable set "$v" --env store-qa --body "$val"
done
```

`CAPGO_BUNDLE_PUBLIC_KEY` must also be present as a **variable**. Stored as a secret it resolves
to an empty string, which silently drops signature verification from the shipped app; both
`ota.yml` and `store-rc.yml` fail closed on that.

## Apple

The bundle identifier is `com.synaplan.app`. It must exist as an *Identifier* in the Developer
portal, and the app must exist in App Store Connect, before an upload can succeed. TestFlight
internal testing does not require App Review, so this path works before the first submission.

| Secret | Where it comes from |
| ------ | ------------------- |
| `APPLE_TEAM_ID` | developer.apple.com → Membership details. Ten characters. |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | An Apple Distribution certificate exported from Keychain Access as `.p12`, **including its private key**, then base64-encoded. |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | The password chosen during that `.p12` export. |
| `IOS_PROVISIONING_PROFILE_BASE64` | An App Store distribution profile for `com.synaplan.app`, downloaded as `.mobileprovision` and base64-encoded. |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect → Users and Access → Integrations. |
| `APP_STORE_CONNECT_ISSUER_ID` | Shown above the key table on the same page. |
| `APP_STORE_CONNECT_PRIVATE_KEY` | The `.p8` file contents, **not** base64, including the `BEGIN`/`END` lines. |

Create the certificate in Xcode under *Settings → Accounts → Manage Certificates → + → Apple
Distribution*, then export it from Keychain Access. Encode both files with:

```bash
base64 -i distribution.p12
base64 -i Synaplan.mobileprovision
```

The App Store Connect key needs the **App Manager** role. Its `.p8` file can be downloaded only
once; a lost key cannot be recovered and has to be replaced.

## Android

Only needed once Android ships. Add the secrets, then set `STORE_PLATFORMS` to `ios,android`.

| Secret | Where it comes from |
| ------ | ------------------- |
| `ANDROID_KEYSTORE_BASE64` | The release keystore, base64-encoded. |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` | Chosen when the keystore is created. |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | A Google Cloud service-account JSON key. |

An app already on Google Play can only be updated with the same signing key, so an existing
keystore must be reused. Create one only for an app that has never been published:

```bash
keytool -genkeypair -v -keystore release.jks -keyalg RSA -keysize 4096 \
  -validity 10000 -alias synaplan
base64 -i release.jks
```

After creating the service account, invite its email address in the Play Console under *Users and
permissions* and grant it release access for the app. Without that invitation the upload fails
even though the key is valid.

## Verifying the setup

`store-rc.yml` builds and signs on a dry run and skips both uploads, which is the honest test for
certificate, profile, and keystore:

```bash
gh workflow run store-rc.yml -f dry_run=true
```

The signed artifacts are attached to the run, so the result can be inspected before anything
reaches a store.

## Backups

The distribution certificate, the `.p8` key, and the Android keystore are not recoverable from
GitHub, and losing the keystore means the published Android app can never be updated again. Keep
an encrypted copy of each, with its passwords, outside this repository. See `docs/SECRETS.md`.
