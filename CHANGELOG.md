# Changelog

## 0.4.1

- Edit left/right button and touch actions together, then apply one complete preset list.
- Confirm both returned values, check per-key availability and preserve unselected keys.
- Restore the previous pair after a rejected or partially confirmed transaction; explain rejected combinations without Playback control.
- Show pending values, current device values and apply results in the control card.
- Verify six basic preset combinations on WF-1000XM4 firmware 2.3.1, including right Ambient, Volume and No function, with original settings restored.

## 0.4.0

- Package a verified drag-to-Applications DMG with a fixed Finder layout, SHA-256 checksum and installation guide.
- Automatically reconnect to the previously selected headset with bounded retry backoff.
- Pause retries while the Mac sleeps and resume discovery after wake.
- Respect manual Disconnect and the Automatically Reconnect preference.
- Continue connection monitoring while an EQ draft is open; reconnect does not replay old ANC/EQ values.
- Close a stalled control session after mandatory reads fail so reconnect can establish a fresh session.
- Prepare the public source repository with MIT notices, CI, contribution/security policies, issue templates and an explicit compatibility matrix.
- Add the cow logo and four real interface screenshots to the README and interface guide.
- Check public files, reachable Git history, PNG metadata and commit emails with a local pre-push hook and CI privacy guard.

## 0.3.0

- Rename the app to OpenSound and add Menu Bar quick controls.
- Add hardened runtime signing, diagnostic log protections, parser/response validation and security regression tests.

## 0.2.0

- English portrait interface, user-selected cow app icon and model-specific product renders.
- Add capability-directed system settings, voice guidance, touch assignment, multipoint and device information.
- Confirm core ANC/EQ and nine additional setting writes/restorations on WF-1000XM4 firmware 2.3.1; retain right-touch reassignment as a known limitation.
