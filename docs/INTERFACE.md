# Interface guide

The app uses an English portrait window. The cow is the application logo; the large hero image is the connected headphone model's product render, with a generic symbol only when a matching image is unavailable.

## Sound

![Sound tab](images/sound.png)

The top row shows separate left/right/case battery readings for earbuds, or a single battery for supported headphones. Missing readings display Unavailable. Sound controls include ANC, Ambient and Off, supported ambient level / voice focus, advertised EQ presets, five editable bands and Clear Bass when compatible. Manual EQ edits are sent only after Apply EQ. A successful operation means a device readback matched the requested value.

## System

![System overview](images/system.png)

Automatically Reconnect resumes a control connection after a loss or Mac wake. The app remembers the selected device locally, retries with backoff, respects manual Disconnect and never sends old ANC/EQ values on reconnect.

Additional sections appear according to capabilities: Audio, Connections, Controls, Device, Playback, Power and System. Paired-device names are hidden until Show device names is expanded. Some settings can be temporarily unavailable because of audio/call state or a device restriction.

![Device controls](images/system-controls.png)

The screenshot shows advertised controls, not a guarantee that every write works. Right-touch reassignment and the tested multipoint changes remain subject to the limits in [feature coverage](FEATURE_COVERAGE.md).

## Status

![Status tab](images/status.png)

Status shows the model, control connection and battery explanation, with a manual refresh action. Closing the window keeps OpenSound running.

## Menu Bar

Click the headphone icon in the macOS Menu Bar for current battery, connect/disconnect, ANC modes, EQ presets, Automatically Reconnect, Show OpenSound and Quit OpenSound. The app's Controls menu uses the same commands. Quit releases the Bluetooth control session. Closing the window alone does not quit. No login item is installed automatically.

Screenshots were captured from the native app on 2026-10-14. Pairing names and device addresses are absent from these images. The app icon was supplied by the project owner; device render provenance is in [the asset notice](../Resources/Devices/NOTICE.md).
