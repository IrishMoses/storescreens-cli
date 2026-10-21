StoreScreens 4.0.1 rejects failed XCUITest runs even when they produced screenshots. It checks the process exit status and recorded test failures before accepting captures, discards images from failed attempts, and preserves the previous successful output. Capture skips Xcode's additional simulator diagnostics archive while retaining failure messages and screenshot attachments in the result bundle.

MCP capture now accepts locale, appearance, screenshot-prefix, concurrency, and retry options. Partial runs preserve unrelated images and manifest entries. The worked example includes a standard-library MCP client, Koubou framing configuration generation, and an ASC CLI upload preview.

Set `code_signing_allowed: true` for applications that require simulator entitlements for Keychain or app-group access. This setting is now preserved in each device's capture runner. Rendering and App Store Connect remain separate operations; Koubou and ASC CLI are the recommended tools.
