# AI Agent Instructions

This file is the single source of truth for all AI coding assistants working on this project.
Tool-specific files (`CLAUDE.md`) point here.

## Product

BlackoutSignal is a single-user macOS menu-bar utility for Apple Silicon Macs (primary target: Mac mini with an external DDC/CI monitor). It provides a one-key "blackout while keeping the video signal alive" mode: the Mac keeps outputting video (so the monitor never shows its "no input" blue screen), DDC/CI dims supported external displays to brightness 0, a pure-black borderless overlay covers every screen, and IOKit power assertions stop idle display/system sleep — all only while blacked out, with the entry-time brightness restored on exit. It is NOT a lock-screen, and it never truly sleeps the Mac. Local development signing only; not distributed via the App Store. **The App Sandbox is intentionally disabled** because Apple Silicon DDC/CI (`IOAVService`) requires IOKit access the sandbox blocks. Deployment target is macOS 26.5 (uses macOS 26 SwiftUI design).

## Project Phase

- **BlackoutSignal (app)**: Core v1 implemented — menu-bar app (`MenuBarExtra`, `.accessory`, no Dock icon), Carbon global hotkey ⌥⌘B, per-screen black overlay with Esc-to-exit + cursor hide, Apple Silicon DDC/CI brightness control (read/record → set 0 → restore) confined to `BSDisplayDDC` (Obj-C), IOKit power assertions, crash-recovery persistence (`BrightnessStore`) with a launch-time restore prompt, and a launch-at-login toggle (`SMAppService.mainApp`). Verified: `xcodebuild` Debug build + code sign succeed; `BrightnessStoreTests` pass; app smoke-launches without crashing. NOT yet verified on real hardware: live DDC dimming/restore, overlay appearance, and the global hotkey require the user's Mac mini + monitor (these black out the screen, so only the user can confirm).

## Development Rules

### Two-Step Confirmation First
- Never start the moment a requirement is stated or changed. Every new or modified requirement first passes through an understand-and-confirm step before any code is written. The only exception is trivial mechanical actions whose intent is obvious (e.g. `git push`, fixing a typo, a one-line rename).
- **Step one — reflect and surface, always in the open before building:**
  - Judge whether the request is sound: is it safe? is it efficient? does it fit the project's scale?
  - Consider whether a better approach exists than the one asked for.
  - State your full understanding of the request, your analysis of it (risks, tradeoffs, anything ill-advised), and your concrete recommendation.
- **Step two — act on the outcome:**
  - If the request is uncertain (multiple approaches with tradeoffs, may affect other features, or ill-suited to the project's scale), wait for the user's confirmation before modifying code.
  - If there is a clearly optimal and safe path, you may proceed without waiting for confirmation — but conspicuously notify the user that you are doing so up front, and on completion state plainly what you changed and why it was the better path.
  - Push back on any request that compromises security, correctness, or runtime efficiency, even when explicitly asked.

### Scope Discipline
- Each task must stay within its stated scope. Do not add, refactor, or "improve" anything outside the current request.
- If the current task logically depends on another unbuilt feature, ask the user before implementing it. Never silently introduce adjacent functionality.

### Coding Standards
- **Source of truth & persistence**: `BlackoutController` (`@MainActor @Observable`) is the single source of truth for blackout state; the SwiftUI menu/settings only read it and call its methods. The ONLY persisted state is the in-progress blackout session (`stableKey → original brightness`), written by `BrightnessStore` to `Application Support/BlackoutSignal/session.json`. That file exists only while blacked out: present at launch ⇒ previous run didn't exit cleanly ⇒ offer recovery. Never hardcode a "default" brightness to restore — always restore the recorded original.
- **Architecture & boundaries**: Layers are `BSDisplayDDC` (Obj-C, all IOKit/`IOAVService`/CoreDisplay private-API usage) → Swift services (`PowerAssertionManager`, `HotKeyManager`, `OverlayManager`, `BrightnessStore`) → `BlackoutController` → SwiftUI (`BlackoutSignalApp`, `AppDelegate`, `Views/`). All private/unsafe C is confined to `BSDisplayDDC`; keep `BrightnessStore` UI-free and unit-tested. The Xcode project uses File System Synchronized groups, so new files under `BlackoutSignal/BlackoutSignal/` are added to the target automatically — no `.pbxproj` edits needed except build settings.
- **Language / framework conventions**: Swift with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (most types are MainActor by default); cross into C callbacks via raw pointers (`Unmanaged`) rather than capturing non-Sendable state. Obj-C↔Swift via `BlackoutSignal-Bridging-Header.h`. Global hotkey via Carbon `RegisterEventHotKey` — chosen specifically to avoid Accessibility/Input-Monitoring prompts; do NOT switch to an `NSEvent` global monitor or `CGEventTap` without re-justifying the added privacy permission.
- **Security boundary**: Single local user; the only control surface is the menu bar + one global hotkey on this machine. No network, no data upload, no execution of downloaded/arbitrary code. DDC/CI must only ever touch VCP `0x10` (luminance); NEVER send power/standby/sleep/input VCP codes (`0xD6` etc.) — those can drop the video signal and reproduce the "no input" screen this app exists to prevent. Sandbox is off by necessity (DDC), so be conservative: do not broaden file/system access beyond what blackout needs.

### Verify & Commit
- After any code change, run the project's verification (e.g. type-check / build / lint) across all affected packages.
- If verification fails, fix the errors first, then verify again.
- After verification passes, automatically commit files that were modified by the agent in the current task and belong to the current task.
- Before committing, inspect dirty files and separate current-task agent edits from unrecognized dirty files. Do not include unrecognized dirty files in commits unless the user explicitly asks to include them.
- If a dirty file's ownership or task relevance cannot be determined safely, stop and ask the user before committing.
- Group commits by coherent change unit. Do not push unless explicitly requested.
- Branching: per-feature work lands on a `feat/*` branch that merges into the mainline. Keep merged `feat/*` branches as historical archives — never delete them (local or remote).
- Commit message format (Conventional Commits):
  ```
  type(scope): short summary

  Detailed description of what changed and why.
  ```
  Types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`.

### Session Handoff
- `notice.md` files are scoped by directory and record durable handoff information for the next agent.
- Root `notice.md` records global, cross-package, or cross-task project information.
- App/package notices record durable facts for that app/package: architecture, contracts, workflows, credentials, known limitations, and package-specific gotchas.
- Update the relevant `notice.md` only when the session creates or discovers information that remains useful beyond the current task or conversation. Do not record pure Q&A, routine progress, temporary decisions, or workflow session/journal details there.
- Ensure any `notice.md` you touch remains accurate and up-to-date within its directory scope.

### End-of-Session Summary
- At the end of each conversation, output a brief summary in 中文 (Chinese). This summary is user-facing.
  ```
  ## Summary
  - **Done**: work completed this round
  - **Key decisions**: tag each [user] or [self], explain the decision
  - **Commits**: list this round's commits (hash, message, files); note any dirty files left out and why
  - **Open/known risks**: issues introduced or discovered this round (omit if none)
  - **Suggested next steps**: 1-3 concrete actionable items
  ```
