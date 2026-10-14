# OpenSound device support

The app discovers paired Sony Bluetooth devices and chooses a service/channel through SDP. Model names alone never enable a control. Supported-function and capability replies select the protocol table, ANC profile, available settings and valid options.

| Device / family | Current status |
|---|---|
| WF-1000XM4, firmware 2.3.1 | Core battery, ANC/Ambient/Off and EQ physically verified on one unit, including writes/readback, restoration and reconnect. Nine additional setting writes/readback/restoration passed; right-touch assignment changes were refused in the test session. |
| Other Sony WH, WF, WI, MDR and LinkBuds models using classic MDR RFCOMM | Paired-device discovery and capability-selected handlers implemented; hardware compatibility remains unverified. Unsupported layouts stay unavailable. |
| Sony devices needing BLE-only control or LE Audio transport | Declarations catalogued; macOS transport/profile implementation not established. |
| Speakers/party devices represented in the shared protocol | Catalogue contains shared declarations; this does not establish headphone-app support for those devices. |
| Sony Account, cloud services and firmware updater | Excluded from this release. |

The tested WF-1000XM4 advertises an Auto ANC profile. Another model's plain dual-ANC inquiry returned an ACK without a matching parameter reply. Selecting the inquiry from advertised capabilities resolved that difference. Service version, support-function identifiers and inquiry bytes represent separate layers and must not be substituted for one another. The device's Bluetooth channel is discovered at runtime.

Hardware write/readback/restoration additionally passed for DSEE, pause on removal, Type 1 Speak to Chat and its sensitivity/resume/voice-focus options, left touch assignment, voice guidance and headphone volume. The right touch assignment responded with its original value after requested changes; the app reported failure. Connection quality, power-off modes, multipoint/source switching and device-side assistant selection were read but not write tested.

Additional typed settings include DSEE, connection quality, pause on removal, Speak to Chat, power-off timers, headphone volume, touch/button assignment, voice guidance, source switching and device-named general settings. Availability depends on the connected model and current device responses. Device-side voice-assistant selection is separate from provider account or application setup.

All-model compatibility still requires physical tests across generations, firmware revisions, transports, battery formats, EQ band counts, ANC profiles, assignments, voice guidance and multipoint behavior. Finding a device or cataloguing its protocol is not proof that every function works. Current implementation and unresolved families are listed in `FEATURE_COVERAGE.md`.
