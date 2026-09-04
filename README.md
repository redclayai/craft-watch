# Craft Watch

A native Apple Watch app for [Craft](https://craft.do): raise your wrist, dictate a task or
note, and it lands in Craft — **with your iPhone locked, or not there at all.**

That last part is the whole reason this exists. The Craft Shortcut approach routes through
Craft's *iPhone* action, so the Watch is only a remote control and the request dies on a
locked phone. This app talks to Craft directly from the Watch.

## How it talks to Craft

Craft has no public REST API. Its only programmable surface is its MCP server, and that
turns out to be a better fit than a REST API would have been:

| | |
|---|---|
| Endpoint | `https://mcp.craft.do/my/mcp` (Streamable HTTP, JSON-RPC 2.0) |
| Auth | OAuth 2.1 — PKCE S256, dynamic client registration, `token_endpoint_auth_method: none` |
| Tools | exactly two: `craft_read` and `craft_write`, each taking one CLI-style `command` string |

Two consequences shaped the design:

1. **No client secret, and refresh tokens are issued.** The Watch can hold the refresh
   token and mint its own access tokens forever, with no phone in the loop. This is what
   makes locked-phone capture work.
2. **Two tools, one string argument each.** No MCP SDK is needed — `URLSession` plus
   `JSONSerialization` covers it in one file, which matters on watchOS.

The commands used are the same ones Craft's own CLI exposes:

```
tasks list --scope active
tasks add --markdown "…" --schedule today
tasks update --id <id> --state done
blocks get --date today          # -> today's Daily Note page id
blocks add --id <pageId> --markdown "…" --position end
```

## Architecture

```
Phone (setup only)                 Watch (does the work)
──────────────────                 ─────────────────────
SetupView                          RootView ── TextFieldLink (dictate)
  └ ASWebAuthenticationSession       ├ TaskRow  (tap = complete)
      OAuth: register → PKCE →       ├ CaptureSheet (complication deep link)
      authorize → token              └ SettingsView
  └ PhoneConnectivity              CraftStore  (@Observable)
      updateApplicationContext  ──▶ WatchConnectivityReceiver
                                   PendingQueue (disk, survives relaunch)
                                   CredentialStore (Keychain, afterFirstUnlock)
                                   CraftMCPClient ──▶ mcp.craft.do
                                   CraftWatchWidget (complication, App Group cache)
```

Deliberate choices worth knowing about:

- **The phone never calls Craft after setup.** It verifies the grant once to read the
  space name, then hands the credentials over and stops. Only one device rotates the
  refresh token, so the two can't invalidate each other.
- **Credentials arrive via `updateApplicationContext`**, which is durable — if the Watch
  is asleep or out of range during setup, WatchConnectivity delivers it later.
- **Capture never fails.** Anything that can't be sent goes to `PendingQueue` on disk and
  is retried on next launch or connect. The haptic distinguishes saved from queued.
- **Completion is optimistic.** The row leaves immediately and is restored if Craft
  rejects it.
- **The complication reads a cached count** from the App Group, so it never blocks on the
  network or on auth. Tapping it deep-links straight into dictation.
- **Tool names are resolved from `tools/list`**, so a rename on Craft's side surfaces a
  clear error instead of a silent 404.

## Build and run

```bash
cd ~/CraftWatch && xcodegen generate && open CraftWatch.xcodeproj
```

`project.xcodeproj` is generated and gitignored — edit `project.yml`, never the project
file. Requires XcodeGen (`brew install xcodegen`).

Targets: `CraftWatch` (iOS companion), `CraftWatch Watch App`, `CraftWatchWidget`.
Bundle IDs live under `ai.redclay.craftwatch`; App Group `group.ai.redclay.craftwatch` is
shared by the Watch app and its widget. Signing is automatic against team `3RPG92BQ9C`.

### First run

1. Run the **CraftWatch** (iOS) scheme on your iPhone, tap **Connect Craft**, approve the
   space in the Craft page that opens.
2. Open **Craft** on the Watch. It picks up the credentials and lists today's tasks.
3. Add the *Craft Tasks* complication to a watch face for one-tap dictation.

### Seeing the UI

The Claude Code live simulator panel does not work on this machine: its helper
(`/Applications/Claude.app/Contents/Helpers/Claude iOS Sim.app`) aborts in
CoreImage/Metal via FBSimulatorControl before it reaches the app, so it crash-loops on
every screenshot. Use simctl instead:

```bash
Scripts/shot.sh [output-dir]     # screenshots every booted simulator
```

### Inspecting the UI without a Craft account

```bash
SIMCTL_CHILD_CRAFT_DEMO=1 xcrun simctl launch <sim-udid> ai.redclay.craftwatch.watchkitapp
```

Seeds a plausible connected state (`CraftStore.seedDemo()`, `#if DEBUG` only) so the main
screen renders without a real grant.

## State of things

Verified:

- Both schemes build clean for Debug and Release.
- `TaskListParser` round-trips real `tasks list` output — ids, done state, schedule vs
  deadline, container names, overdue logic, curly quotes and em dashes intact.
- Command quoting round-trips through Craft (tested live against a real space with
  embedded `"` and `'`).
- OAuth chain confirmed live against `mcp.craft.do`: resource metadata → authorization
  server metadata → dynamic client registration returns a usable public `client_id`.
- Watch app launches and renders in the simulator, unconnected and connected.
- WatchConnectivity works end to end against a paired simulator pair: activation
  completes, the counterpart resolves to the paired Watch, and the phone correctly
  reports the Watch app as available. Zero `has not been activated`, zero
  `counterpart app not installed`, zero `pairingIDs no longer match`.

Not yet exercised, because it needs a real Craft sign-in:

- The OAuth round trip through `ASWebAuthenticationSession`.
- Phone → Watch credential handoff (the transport is verified; the payload is not).
- Refresh-token rotation on the Watch.
- Capture and completion against a live space from the Watch.

### Expected console noise

Running the iOS app on a simulator with no paired Watch logs these from `com.apple.wcd`
(the WatchConnectivity daemon, not this app) — they are inherent to having no counterpart
and clear once a Watch is paired:

```
WCSession is not paired
WCSession counterpart app not installed
dropping as pairingIDs no longer match
Application context data is nil
```

`WCSession has not been activated` is *not* in that category. If it reappears, something
is reading `isPaired` / `isWatchAppInstalled` / `applicationContext` before activation
completes — see the comment at the top of `PhoneConnectivity`.

To pair simulators, run the **CraftWatch Watch App** scheme once, or pair them under
Xcode ▸ Window ▸ Devices and Simulators ▸ Simulators.

Not built yet: an app icon, MCP-backed natural-language commands ("add a follow-up with
Ryan tomorrow"), and background refresh to keep the complication warm without opening
the app.
