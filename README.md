![StoreScreens — XCUITest Screenshot Orchestration](assets/banner.png?v=interfaces)

# StoreScreens

**XCUITest Screenshot Orchestration**

StoreScreens sets up simulators, runs your XCUITest screenshot flows, and collects authentic raw captures across devices, locales, and appearances. It provides a Swift CLI and a capture-only MCP server.

## Why StoreScreens?

Taking a screenshot is easy. The valuable work is making the whole run repeatable: preparing the right app state, switching devices and languages, waiting for the UI to finish rendering, and checking the results.

StoreScreens provides one capture workflow across your apps, so each project does not need its own simulator setup and collection scripts. Your XCUITests define app state, navigation, and explicit waits. StoreScreens prepares simulators and paired devices, runs those tests, rejects failed or empty captures, and collects named PNGs with a manifest for review. Failed runs leave previous successful captures intact.

The division of work is simple:

- **StoreScreens:** prepare, capture, and validate test results.
- **[Koubou](https://github.com/bitomule/Koubou):** compose and render screenshots, including device frames, captions, and localization.
- **[ASC CLI](https://asccli.sh/):** upload screenshots and manage App Store Connect releases.

Koubou and ASC CLI are our recommendations, not required dependencies. Use the screenshot renderer and App Store Connect command-line tool you prefer. StoreScreens focuses on capture and does not manage their credentials.

## Install

Prebuilt binaries require an Apple silicon Mac with macOS 14 or later. Capture requires Xcode and the simulator runtimes your application needs.

### mise

```sh
mise use -g github:ciscoriordan/storescreens-cli@4.1.0
storescreens --version
```

### Homebrew

```sh
brew install ciscoriordan/tap/storescreens
```

### curl

```sh
curl -fsSL https://raw.githubusercontent.com/ciscoriordan/storescreens-cli/main/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
```

The curl installer downloads the latest release into `~/.local/bin`, including the MCP server and XCUITest template resource bundle. Add that directory to your shell's PATH for future sessions, or set `INSTALL_DIR` when running the installer to choose another location.

### Build from source

```sh
swift build -c release
.build/release/storescreens --help
```

### Agent skill and MCP setup

From your application's project directory, install the [StoreScreens agent skill](https://github.com/ciscoriordan/storescreens-skill) with Node.js 22.20 or later:

```sh
npx skills add ciscoriordan/storescreens-skill
```

Choose your coding agent when prompted. Add `-g` to install across projects, then start a new agent session and ask it to set up screenshot capture for your app.

For MCP, add a local stdio server that launches `storescreens-mcp`. With the Codex CLI:

```sh
codex mcp add storescreens -- storescreens-mcp
```

For a mise-managed installation, use `mise exec -- storescreens-mcp` as the server command. Other clients can use [mcp.json.example](mcp.json.example). See the [Codex MCP setup guide](https://learn.chatgpt.com/docs/extend/mcp) for app settings.

### Koubou for screenshot rendering

[Koubou](https://github.com/bitomule/Koubou) adds layouts, device frames, captions, and localization to your raw captures. It is optional; use another renderer if you prefer.

```sh
brew install bitomule/tap/koubou
kou --version
```

With a mise-managed Python, you can instead run `python3 -m pip install koubou`. Run `kou setup-html` to prepare HTML rendering, or `kou install-skills` to add Koubou's agent skills. See the [Koubou installation guide](https://github.com/bitomule/Koubou#-installation).

### ASC CLI for App Store Connect

[ASC CLI](https://asccli.sh/) manages App Store Connect and uploads your rendered screenshots. It is also optional and has its own credentials. StoreScreens capture makes no App Store Connect requests.

```sh
brew install asc
asc --version
```

You can also install it with `curl -fsSL https://asccli.sh/install | bash`. Register your App Store Connect API key with `asc auth login`; `asc auth login --help` lists the key ID, issuer ID, and private-key options. Run `asc install-skills` if you want its agent skills.

## Capture workflow

Run these commands from the application's project directory:

```sh
storescreens init
storescreens setup
# Add navigation and explicit waits to the generated ScreenshotTests.swift.
storescreens prepare
storescreens capture
kou generate koubou.yml
# Review the rendered screenshots, then upload them with ASC CLI.
```

`setup` generates an XCUITest harness that writes named PNGs directly to the capture cache and also saves XCTAttachments. You supply the navigation for each screen. The harness reads StoreScreens' locale, launch arguments, and screenshot filters. Existing validated application-specific harnesses can continue to be used.

A capture configuration:

```yaml
project: MyApp.xcodeproj
scheme: MyApp
output_dir: screenshots/raw
result_bundle_dir: screenshots/results

devices:
  - simulator: iPhone 18 Pro Max
  - simulator: iPad Pro 13-inch (M5)
    tests: [ScreenshotTests/testTabletScreens]

locales: [en-US, el]
appearances: [light, dark]
screenshots: [Home, Search, Detail]
test_target: MyAppUITests
test_class: ScreenshotTests
```

Use `storescreens list` to choose names installed on the machine. iPhone 17 Pro Max uses an iOS 26 runtime; iPhone 18 Pro Max uses iOS 27. Native macOS targets use `platform: macOS` with a name such as `Mac 2560x1600`.

The configuration also accepts `workspace` instead of `project`, `launch_arguments`, `derived_data_path`, `warmup_run`, `preflight`, `dismiss_system_alerts`, `status_bar`, `status_bar_arguments`, `keep_runs`, `keep_old_previews`, `locale_flags`, and `log_level`. `keep_runs: 1` merges successful captures into the output directory; zero keeps every run, and larger values keep that many timestamped runs.

Set `code_signing_allowed: true` when the app needs signed simulator entitlements for Keychain or app-group access. Capture uses the project's simulator signing settings in that case. The default remains `false`; no App Store Connect credentials are required.

Use `screenshot_appearances: {Home: dark}` to restrict an individual screenshot to an appearance. This requires an explicit `screenshots` list. Unrestricted screenshots run in the top-level appearances. The appearance stays in the output path and manifest, so downstream renderers receive the correct source image.

### Apple Watch

Watch-only apps and Watch apps with an iPhone companion use the same CLI and MCP capture workflow. Install a watchOS simulator runtime in Xcode and list Watch devices with `storescreens list --include-watch`. Select the Watch app's scheme when generating the configuration and harness:

```sh
storescreens init --scheme MyWatchApp
storescreens setup --scheme MyWatchApp
```

The scheme must include a watchOS UI Testing Bundle targeting the Watch app. Add navigation to the generated test, then run `storescreens prepare` and `storescreens capture`. A Watch configuration looks like this; use simulator names installed on your machine:

```yaml
project: MyApp.xcodeproj
scheme: MyWatchApp
devices:
  - simulator: Apple Watch Series 12 (46mm)
    platform: watchOS
    # For an app that requires an iPhone companion:
    # companion: iPhone 18 Pro
    # companion_scheme: MyPhoneApp
locales: [en-US, el]
appearances: [dark]
test_target: MyWatchAppUITests
test_class: ScreenshotTests
screenshots: [Home, Detail]
output_dir: screenshots/watch/raw
result_bundle_dir: screenshots/watch/results
```

`platform: watchOS` is inferred from the simulator when omitted. `companion` pairs and boots the specified iPhone with the Watch; an existing pairing with another phone is preserved and reported as an error. Set `companion_scheme` to the iPhone app's separate iOS scheme to build, install, and launch it before the Watch tests. Without that field, install and prepare the companion app separately. Keep the iPhone target out of the Watch scheme's test build action. Paired Watch devices run sequentially so activating a pair cannot interrupt another capture. Capture the phone and Watch with separate configurations and schemes.

Watch captures use dark appearance, including when `appearances` is omitted. Light-only selections are rejected. iOS appearance and status-bar overrides do not run on watchOS. Raw PNGs, Watch size labels, locale metadata, partial reruns, and retained `.xcresult` bundles work through both CLI and MCP. Rendering and uploads remain separate operations.

## Commands

| Command | Purpose |
| --- | --- |
| `list` | List available simulators and their screen sizes |
| `init` | Generate capture configuration |
| `setup` | Generate an editable XCUITest screenshot harness |
| `prepare` | Boot simulators, set supported status bars, prepare companion apps, or install `--app MyApp.app` |
| `capture` | Run tests and collect raw screenshots |
| `collect` | Extract named attachments from an existing `.xcresult` |
| `check` | Check source for capture problems and device assumptions |
| `screenshot` | Capture a running simulator's current screen |
| `migrate-config` | Preserve a version 3 configuration and write capture settings |

Capture flags include `--locale`, `--appearance`, `--only`, `--no-parallel`, `--retries`, `--derived-data-path`, `--result-bundle-dir`, `--skip-check`, and `--verbose`. `--xcresult` collects XCTAttachments instead of filesystem PNGs. `--mode simple` captures an installed launch state after building the app; it does not navigate through screens. It uses Xcode's build settings to locate the actual app, including Release and custom product directories, without selecting a stale Debug build. `--keep-alive` applies to simple capture.

A narrowed run preserves manifest entries outside its locale or appearance scope. `--only Home,Search` replaces matching screenshots while keeping other names. Full runs replace the manifest. A failed test rejects the capture even if it saved screenshots; failed captures do not publish staged images over previous successful captures. Simultaneous capture processes are rejected because the test harness uses shared cache hints.

To collect results from a separate test run:

```sh
storescreens collect --result-bundle TestResults.xcresult \
  --simulator 'iPhone 18 Pro Max' --locale en-US --appearance light \
  --output screenshots/raw
```

Set `result_bundle_dir` to preserve original result bundles and test diagnostics in a unique directory per invocation. Without it, result bundles are temporary. Filesystem PNGs remain the primary capture path.

Capture disables Xcode's additional simulator diagnostics collection after failed tests. Failure messages and screenshot attachments remain in the `.xcresult`; the capture result does not wait for a full simulator diagnostics archive.

## Handoff to Koubou and ASC CLI

Raw PNGs work with other screenshot renderers and upload tools too. Koubou and ASC CLI are our recommended combination, and the examples below use them.

`manifest.json` records the scheme, generator version, timestamp, simulator, screen-size label, locale, appearance, screenshot names, and relative PNG paths. For example, a capture can produce `en-US/light/iPhone_6.9_Home.png`. Reference those PNG paths as Koubou image assets; keep the rendering configuration, templates, fonts, reviewed copy, and capture configuration in the application's source control.

StoreScreens never uploads automatically. Render and review with Koubou, then use `asc screenshots upload` or ASC CLI's reviewed upload workflow. Keep existing approved device sizes, locale coverage, and copy during migration. A tooling change does not require replacing a queued App Store submission.

## Upgrading from version 3

Version 4 removes the built-in renderer, bezel library, templates, translations, search previews, Wall of Apps, binary upload, and all App Store Connect commands and MCP tools. Use separate rendering and App Store Connect tools; we recommend Koubou and ASC CLI. Existing credentials, including files under `~/.storescreens/`, are left in place.

Old `render`, `app_store_connect`, `search_preview`, and `upload` sections cause an actionable configuration error. To convert the capture settings:

```sh
storescreens migrate-config --config storescreens.yml
```

This saves an exact, private-permission `storescreens.yml.v3-backup` before writing the capture-only file. It transfers `render.slides.<name>.appearance` to `screenshot_appearances`, and preserves device selections, locales, launch arguments, test selectors, and screenshot ordering. It refuses to overwrite an existing backup. Port reviewed captions and layouts from that backup into Koubou; they are not automatically translated between rendering engines. Keep backups containing credentials out of source control.

## MCP

Configure `storescreens-mcp` as a stdio server; see [mcp.json.example](mcp.json.example). The server exposes only `capture`, `get_capture_status`, `get_capture_result`, `check`, `list_simulators`, `list_screenshots`, `get_screenshot`, `take_screenshot`, `read_config`, and `write_config`. Capture returns a task ID and streams progress through status polling. It uses the same capture implementation as the CLI.

The MCP `capture` tool accepts `locales`, `appearances`, `only`, `no_parallel`, and `retries`, as well as configuration and DerivedData paths. Use `list_simulators` with `include_watch: true` to discover Watch devices. Narrowed MCP runs preserve the other images and manifest entries just like the CLI. See the [complete capture and Koubou example](examples/README.md) for a standard-library MCP client, partial reruns, framing configurations, and an ASC CLI upload preview.

## Development

```sh
swift test
bash scripts/test-mcp.sh
# Requires xcodegen and an iOS 27 runtime; creates and removes its own simulator.
python3 scripts/smoke-capture.py
# Requires xcodegen plus watchOS and iOS runtimes.
python3 scripts/smoke-watch-capture.py --sanity
python3 scripts/smoke-watch-capture.py
```

The simulator smoke test navigates a fixture app, captures two authentic screens, verifies partial reruns, then saves a screenshot and deliberately fails a test. It requires a nonzero capture exit and byte-identical previous output, verifies recovery, and collects the original images from a preserved `.xcresult`. It keeps its temporary artifacts for inspection.

The Watch smoke test generates watch-only and companion-app fixtures. It checks configuration and harness generation, CLI and MCP capture, pairing, Watch dimensions, attachment collection, partial reruns, and preservation of previous output after a failed test. `--sanity` runs one watch-only capture first. The script removes only its own simulators and retains its artifacts.

Banner assets are generated from the original app icon in `assets/logo.png` and bundled OFL-licensed IBM Plex Sans fonts. Run `python3 scripts/generate-banner.py` after changing the tagline or artwork; it requires `fonttools[woff]`, `cairosvg`, and the Cairo library. The generator produces the README banner, an SVG source, and the social image.

## License

MIT.
