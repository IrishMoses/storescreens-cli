# StoreScreens

StoreScreens sets up simulators, runs your XCUITest screenshot flows, and collects authentic raw captures across devices, locales, and appearances. It provides a Swift CLI and a capture-only MCP server.

StoreScreens is active again with a narrower scope in version 4. We recommend [Koubou](https://github.com/bitomule/Koubou) for screenshot composition, device frames, captions, localization, and rendering, and [ASC CLI](https://asccli.sh/) for App Store Connect and Apple Ads management, including uploads. StoreScreens does not implement those features or manage their credentials.

## Install

Requires macOS 14 or later, Xcode, and the simulator runtimes your application needs. On a Mac using mise:

```sh
mise use -g github:ciscoriordan/storescreens-cli@4.0.0
storescreens --version
```

To build from source:

```sh
swift build -c release
.build/release/storescreens --help
```

Koubou and ASC CLI are separate tools. Follow their installation instructions; capture itself requires neither tool and makes no App Store Connect requests.

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

Use `screenshot_appearances: {Home: dark}` to restrict an individual screenshot to an appearance. This requires an explicit `screenshots` list. Unrestricted screenshots run in the top-level appearances. The appearance stays in the output path and manifest, so downstream renderers receive the correct source image.

## Commands

| Command | Purpose |
| --- | --- |
| `list` | List available simulators and their screen sizes |
| `init` | Generate capture configuration |
| `setup` | Generate an editable XCUITest screenshot harness |
| `prepare` | Boot configured simulators, set status bars, optionally install `--app MyApp.app` |
| `capture` | Run tests and collect raw screenshots |
| `collect` | Extract named attachments from an existing `.xcresult` |
| `check` | Check source for capture problems and device assumptions |
| `screenshot` | Capture a running simulator's current screen |
| `migrate-config` | Preserve a version 3 configuration and write capture settings |

Capture flags include `--locale`, `--appearance`, `--only`, `--no-parallel`, `--retries`, `--derived-data-path`, `--result-bundle-dir`, `--skip-check`, and `--verbose`. `--xcresult` collects XCTAttachments instead of filesystem PNGs. `--mode simple` captures an installed launch state after building the app; it does not navigate through screens. `--keep-alive` applies to simple capture.

A narrowed run preserves manifest entries outside its locale or appearance scope. `--only Home,Search` replaces matching screenshots while keeping other names. Full runs replace the manifest. Failed captures do not publish staged images over previous successful captures. Simultaneous capture processes are rejected because the test harness uses shared cache hints.

To collect results from a separate test run:

```sh
storescreens collect --result-bundle TestResults.xcresult \
  --simulator 'iPhone 18 Pro Max' --locale en-US --appearance light \
  --output screenshots/raw
```

Set `result_bundle_dir` to preserve original result bundles and test diagnostics in a unique directory per invocation. Without it, result bundles are temporary. Filesystem PNGs remain the primary capture path.

## Handoff to Koubou and ASC CLI

`manifest.json` records the scheme, generator version, timestamp, simulator, screen-size label, locale, appearance, screenshot names, and relative PNG paths. For example, a capture can produce `en-US/light/iPhone_6.9_Home.png`. Reference those PNG paths as Koubou image assets; keep the Koubou configuration, templates, fonts, reviewed copy, and capture configuration in the application's source control.

StoreScreens never uploads automatically. Render and review with Koubou, then use `asc screenshots upload` or ASC CLI's reviewed upload workflow. Keep existing approved device sizes, locale coverage, and copy during migration. A tooling change does not require replacing a queued App Store submission.

## Upgrading from version 3

Version 4 removes the built-in renderer, bezel library, templates, translations, search previews, Wall of Apps, binary upload, and all App Store Connect commands and MCP tools. Use Koubou and ASC CLI directly for those operations. Existing credentials, including files under `~/.storescreens/`, are left in place.

Old `render`, `app_store_connect`, `search_preview`, and `upload` sections cause an actionable configuration error. To convert the capture settings:

```sh
storescreens migrate-config --config storescreens.yml
```

This saves an exact, private-permission `storescreens.yml.v3-backup` before writing the capture-only file. It transfers `render.slides.<name>.appearance` to `screenshot_appearances`, and preserves device selections, locales, launch arguments, test selectors, and screenshot ordering. It refuses to overwrite an existing backup. Port reviewed captions and layouts from that backup into Koubou; they are not automatically translated between rendering engines. Keep backups containing credentials out of source control.

## MCP

Configure `storescreens-mcp` as a stdio server; see [mcp.json.example](mcp.json.example). The server exposes only `capture`, `get_capture_status`, `get_capture_result`, `check`, `list_simulators`, `list_screenshots`, `get_screenshot`, `take_screenshot`, `read_config`, and `write_config`. Capture returns a task ID and streams progress through status polling. It uses the same capture implementation as the CLI.

## Development

```sh
swift test
bash scripts/test-mcp.sh
# Requires xcodegen and an iOS 27 runtime; creates and removes its own simulator.
python3 scripts/smoke-capture.py
```

The simulator smoke test navigates a fixture app, captures two authentic screens, verifies the raw manifest, and collects the same images from a preserved `.xcresult`. It keeps its temporary artifacts for inspection.

## License

MIT. Historical version 3 source and releases remain available in Git history and GitHub releases.
