#!/usr/bin/env python3
"""Run real XCUITest capture and xcresult collection on an isolated simulator.

Requires Xcode, an iOS 27 runtime, and xcodegen. Keeps artifacts in a temporary
directory for inspection and removes only the simulator this script creates.
"""
import json
import hashlib
from pathlib import Path
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / ".build/debug/storescreens"
ARTIFACTS = Path(tempfile.mkdtemp(prefix="storescreens-smoke-"))


def run(*args, **kwargs):
    print("Running:", " ".join(str(arg) for arg in args), flush=True)
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


run("swift", "build", cwd=ROOT)
(ARTIFACTS / "App").mkdir()
(ARTIFACTS / "UITests").mkdir()
(ARTIFACTS / "App/App.swift").write_text('''import SwiftUI
@main struct CaptureSmokeApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack {
                    Text("Capture smoke test").accessibilityIdentifier("home")
                    NavigationLink("Open details") {
                        Text("A second authentic app screen").accessibilityIdentifier("detail")
                    }.accessibilityIdentifier("details")
                }.navigationTitle("StoreScreens")
            }
        }
    }
}
''')
template = (ROOT / "Sources/storescreens-cli/Resources/ScreenshotTests.swift.template").read_text()
flow = '''        XCTAssertTrue(app.staticTexts["home"].waitForExistence(timeout: 10))
        takeScreenshot(named: "Home")
        app.buttons["details"].tap()
        XCTAssertTrue(app.staticTexts["detail"].waitForExistence(timeout: 10))
        takeScreenshot(named: "Detail")
'''
(ARTIFACTS / "UITests/ScreenshotTests.swift").write_text(template.replace("{{SCREENSHOT_CALLS}}", flow))
(ARTIFACTS / "project.yml").write_text('''name: CaptureSmoke
options:
  bundleIdPrefix: com.example.storescreens
  deploymentTarget:
    iOS: "26.0"
settings:
  base:
    GENERATE_INFOPLIST_FILE: YES
    CODE_SIGNING_ALLOWED: NO
    TARGETED_DEVICE_FAMILY: "1,2"
targets:
  CaptureSmoke:
    type: application
    platform: iOS
    sources: [App]
  CaptureSmokeUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [UITests]
    dependencies:
      - target: CaptureSmoke
schemes:
  CaptureSmoke:
    build:
      targets:
        CaptureSmoke: all
    test:
      targets: [CaptureSmokeUITests]
''')
run("xcodegen", "generate", "--spec", ARTIFACTS / "project.yml", "--project", ARTIFACTS)
name = "StoreScreensSmoke-" + uuid.uuid4().hex[:8]
created = run("xcrun", "simctl", "create", name,
              "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro",
              "com.apple.CoreSimulator.SimRuntime.iOS-27-0", capture_output=True, text=True)
udid = created.stdout.strip()
config = f'''project: CaptureSmoke.xcodeproj
scheme: CaptureSmoke
devices:
  - simulator: {name}
locales: [en-US]
appearances: [light]
screenshots: [Home, Detail]
test_target: CaptureSmokeUITests
test_class: ScreenshotTests
output_dir: captures
result_bundle_dir: results
derived_data_path: {ARTIFACTS}/DerivedData
preflight: false
'''
(ARTIFACTS / "storescreens.yml").write_text(config)
try:
    run(BINARY, "prepare", cwd=ARTIFACTS)
    run(BINARY, "capture", "--no-parallel", "--retries", "0", cwd=ARTIFACTS)
    original_bundle = next((ARTIFACTS / "results").glob("*/*.xcresult"))
    manifest = json.loads((ARTIFACTS / "captures/manifest.json").read_text())
    names = {shot["name"] for device in manifest["devices"] for shot in device["screenshots"]}
    assert names == {"Home", "Detail"}, names
    for device in manifest["devices"]:
        for shot in device["screenshots"]:
            assert (ARTIFACTS / "captures" / shot["filename"]).stat().st_size > 1000
    run(BINARY, "capture", "--no-parallel", "--retries", "0", "--locale", "el", "--only", "Home", cwd=ARTIFACTS)
    narrowed = json.loads((ARTIFACTS / "captures/manifest.json").read_text())
    by_locale = {device["locale"]: {shot["name"] for shot in device["screenshots"]} for device in narrowed["devices"]}
    assert by_locale == {"en-US": {"Home", "Detail"}, "el": {"Home"}}, by_locale

    def output_hashes():
        return {str(path.relative_to(ARTIFACTS / "captures")): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in (ARTIFACTS / "captures").rglob("*") if path.is_file()}

    before_failure = output_hashes()
    existing_bundles = set((ARTIFACTS / "results").glob("*/*.xcresult"))
    failing_flow = '''        XCTAssertTrue(app.staticTexts["home"].waitForExistence(timeout: 10))
        takeScreenshot(named: "Home")
        XCTFail("Deliberate failure after saving Home")
'''
    test_source = ARTIFACTS / "UITests/ScreenshotTests.swift"
    test_source.write_text(template.replace("{{SCREENSHOT_CALLS}}", failing_flow))
    failed = subprocess.run([str(BINARY), "capture", "--no-parallel", "--retries", "0"],
                            cwd=ARTIFACTS, capture_output=True, text=True)
    (ARTIFACTS / "failed-capture.log").write_text(failed.stdout + failed.stderr)
    assert failed.returncode != 0, "A failed test was accepted as a successful capture"
    assert "Deliberate failure after saving Home" in failed.stdout + failed.stderr
    assert output_hashes() == before_failure, "A failed capture changed the previous output"
    failed_bundles = set((ARTIFACTS / "results").glob("*/*.xcresult")) - existing_bundles
    assert len(failed_bundles) == 1, failed_bundles
    failed_export = ARTIFACTS / "failed-attachments"
    run("xcrun", "xcresulttool", "export", "attachments", "--path", next(iter(failed_bundles)),
        "--output-path", failed_export)
    assert list(failed_export.rglob("*.png")), "The failing test did not save its screenshot"

    test_source.write_text(template.replace("{{SCREENSHOT_CALLS}}", flow))
    run(BINARY, "capture", "--no-parallel", "--retries", "0", "--locale", "en-US", "--only", "Home", cwd=ARTIFACTS)
    run(BINARY, "collect", "--result-bundle", original_bundle, "--simulator", name,
        "--output", "collected", "--locale", "en-US", "--appearance", "light", cwd=ARTIFACTS)
    collected = json.loads((ARTIFACTS / "collected/manifest.json").read_text())
    collected_names = {shot["name"] for device in collected["devices"] for shot in device["screenshots"]}
    assert {"Home", "Detail"}.issubset(collected_names), collected_names
    print(f"Capture, failure preservation, recovery, and collection passed. Artifacts: {ARTIFACTS}", flush=True)
finally:
    subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True)
    subprocess.run(["xcrun", "simctl", "delete", udid], check=True)
