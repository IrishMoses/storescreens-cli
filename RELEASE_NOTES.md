StoreScreens 4.1.0 adds Apple Watch screenshot capture through the CLI and MCP. Watch app schemes use watchOS build destinations, deployment targets, test bundles, and build products. `init --scheme` and `setup --scheme` configure the Watch app's capture harness.

Add `companion` to a Watch device to pair and boot its iPhone simulator, and `companion_scheme` to build, install, and launch the phone app using its own iOS scheme. Existing pairings with a different phone are preserved and reported as configuration errors. Paired captures run sequentially. Watch screenshots use dark appearance and skip iOS status-bar overrides; locale capture, partial reruns, failure preservation, and retained result bundles work through the existing capture pipeline.

The repository includes a reproducible watch-only and companion-app simulator validation script. Rendering and App Store Connect remain separate operations; Koubou and ASC CLI are recommended, optional downstream tools.
