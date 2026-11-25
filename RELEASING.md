# Releasing Basilisk (signing + notarization)

`app/build_app.sh` signs with Developer ID + hardened runtime and notarizes **when the
cert and credentials are present**, and falls back to ad-hoc signing for local dev when
they aren't. The GitHub Actions workflow in `.github/workflows/release.yml` does the same
on CI when you push a `v*` tag.

Everything below is one-time account setup — only you can do it (it needs your Apple
Developer org login). None of it blocks local development, which keeps working as-is.

**Your account (read from the dev cert already on this machine):**
- Org / team name: **GramNY Inc** — this is what will appear on releases, not your personal name.
- Team ID: **`Q6VZV3RC8P`**
- The Developer ID cert, once created, will read `Developer ID Application: GramNY Inc (Q6VZV3RC8P)`.
- Note: the cert currently installed is **Apple Development** (good for stable local signing /
  persistent permissions, but *not* notarizable). You still need to create a **Developer ID
  Application** cert for releases — step 1 below.

## 1. Create the Developer ID Application certificate

Easiest via Xcode: **Settings → Accounts → (your org) → Manage Certificates → + →
Developer ID Application**. This creates the cert and its private key in your keychain.

Verify:

```bash
security find-identity -v -p codesigning
```

You should see one line containing `Developer ID Application: <Org Name> (TEAMID)`.
That full quoted string is your **signing identity**; the 10-char `TEAMID` is your team id.
(Your org name — not your legal name — is what's embedded and shown to users.)

## 2. Create an app-specific password for notarization

At <https://account.apple.com> → Sign-In & Security → App-Specific Passwords, make one
(e.g. "basilisk-notary"). Copy it.

## 3. Local signed + notarized build

Store the notary credentials once under a profile named `basilisk`:

```bash
xcrun notarytool store-credentials basilisk --apple-id YOU@ORG.COM --team-id TEAMID --password APP_SPECIFIC_PASSWORD
```

Then build:

```bash
BASILISK_NOTARY_PROFILE=basilisk ./app/build_app.sh
```

(Plain `./app/build_app.sh` still does a signed-but-not-notarized build if the cert is
installed, or ad-hoc if not.)

## 4. GitHub Actions release

Export the cert + key as a `.p12` (Keychain Access → select the cert **and** its private
key → right-click → Export → .p12, set a password), then base64 it:

```bash
base64 -i Certificates.p12 | pbcopy
```

Add these repo secrets (**Settings → Secrets and variables → Actions**):

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | the base64 string from above |
| `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` export password |
| `KEYCHAIN_PASSWORD` | any random string (temp CI keychain) |
| `SIGN_IDENTITY` | `Developer ID Application: <Org Name> (TEAMID)` |
| `NOTARY_APPLE_ID` | your Apple ID email |
| `NOTARY_TEAM_ID` | `TEAMID` |
| `NOTARY_PASSWORD` | the app-specific password |

Then cut a release:

```bash
git tag v1.2
git push --tags
```

The workflow builds, signs, notarizes, staples, and attaches `Basilisk.zip` to a new
GitHub Release.

## Notes

- **Runner macOS version:** the workflow uses `macos-15`. Basilisk targets macOS 27, so
  CI builds will only succeed once a runner image ships the macOS 27 SDK / matching Xcode.
  Bump `runs-on:` then. Until then, local builds (your machine) are the release path.
- **Bundle id:** currently `local.basilisk.v4pro`. For a public app you may want your
  org's reverse-DNS (e.g. `com.yourorg.basilisk`) — set `BASILISK_BUNDLE_ID` when building.
  Changing it resets the app's macOS permission grants, so decide before you distribute.
