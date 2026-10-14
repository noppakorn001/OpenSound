# Changelog

## 0.4.0

- Automatically reconnect to the previously selected headset with bounded retry backoff.
- Pause retries while the Mac sleeps and resume discovery after wake.
- Respect manual Disconnect and the Automatically Reconnect preference.
- Continue connection monitoring while an EQ draft is open; reconnect does not replay old ANC/EQ values.
- Close a stalled control session after mandatory reads fail so reconnect can establish a fresh session.
- Prepare the public source repository with MIT notices, CI, contribution/security policies, issue templates and an explicit compatibility matrix.

## 0.3.0

- Rename the app to OpenSound and add Menu Bar quick controls.
- Add hardened runtime signing, diagnostic log protections, parser/response validation and security regression tests.

## 0.2.0

- English portrait interface, user-selected cow app icon and model-specific product renders.
- Add capability-directed system settings, voice guidance, touch assignment, multipoint and device information.
- Confirm core ANC/EQ and nine additional setting writes/restorations on WF-1000XM4 firmware 2.3.1; retain right-touch reassignment as a known limitation.
