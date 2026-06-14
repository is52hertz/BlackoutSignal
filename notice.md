# notice.md — BlackoutSignal (root)

Durable handoff facts for this repo. Keep accurate; don't log routine progress here.

## Build / run / test

- Open: `BlackoutSignal/BlackoutSignal.xcodeproj` (Xcode 26.5, Apple Silicon, macOS 26.5 deployment target).
- Build:  `xcodebuild -scheme BlackoutSignal -destination 'platform=macOS' -configuration Debug build`
- Test (logic only; skip UI tests — windowless menu-bar app): `xcodebuild -scheme BlackoutSignal -destination 'platform=macOS' -only-testing:BlackoutSignalTests test`
- The app is a menu-bar (`LSUIElement`) accessory app: no Dock icon, no main window. After launch, look in the macOS menu bar (moon icon).

## Hardware-only verification (cannot be automated here)

DDC dimming/restore, the black overlay, and the global hotkey can only be confirmed on the user's real Mac mini + DDC/CI monitor — exercising them blacks out the screen. CI/agents can verify build + unit tests + a no-crash smoke launch only. Don't claim live DDC works without the user confirming on hardware.

## Why the App Sandbox is OFF (do not "fix" this)

Apple Silicon DDC/CI uses the private `IOAVService` API, which needs IORegistry access the App Sandbox blocks. `ENABLE_APP_SANDBOX = NO` is required and acceptable (local signing, no App Store). Hardened Runtime stays ON; no special entitlement is needed for `IOAVService`.

## DDC/CI implementation (BSDisplayDDC.m)

- Confines ALL private-API usage: `IOAVServiceCreateWithService` / `IOAVServiceReadI2C` / `IOAVServiceWriteI2C` (from IOKit, autolinked) and `CoreDisplay_DisplayCreateInfoDictionary` (CoreDisplay — linked via `OTHER_LDFLAGS = -framework CoreDisplay`).
- Modeled on the proven `waydabber/m1ddc` approach: enumerate online displays, map each to its External `DCPAVServiceProxy` by matching the display's `IODisplayLocation` IORegistry path, then talk DDC over I2C. Chip `0x37`, data addr `0x51`, VCP `0x10` (luminance). Read = send "get VCP" request then read 12-byte reply (max at bytes 6–7, current at 8–9, big-endian). Write = `[0x84,0x03,0x10,hi,lo,checksum]`.
- HARD RULE: only ever touch VCP `0x10`. Never send power/standby/sleep/input codes — they can drop the video signal and reproduce the "no input" screen.
- A display is dimmed only if its current brightness was readable (so it can be restored); otherwise it relies on the overlay. Restore writes the exact recorded value, never a default.

## Crash recovery

`BrightnessStore` writes `Application Support/BlackoutSignal/session.json` on enter (before dimming) and deletes it on clean restore. Present at launch ⇒ offer recovery. Keyed by `BSDisplayDDC.stableKey` (`vendor:model:serial`, else UUID, else `id:<n>`) so it survives reboot/replug.

## Git

Work is on branch `feat/blackout-core` (mainline is `main`). Not a remote yet; nothing pushed.
