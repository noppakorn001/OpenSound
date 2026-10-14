# Feature coverage

The inventory is generated from four pinned protocol headers and matched Sound Connect 13.2.0 Objective-C metadata. It inventories device-control declarations, not all app imports or marketing features. Catalogue coverage and implemented controls are separate.

249 inquiry declarations, 230 advertised function identifiers, and 1294 packet contracts are recorded in `feature-catalog.json`.

| Subsystem | Inquiry declarations | Coverage |
|---|---:|---|
| Alert | 9 | Protocol catalogue; implementation varies by typed handler and device capability |
| Audio | 14 | Protocol catalogue; implementation varies by typed handler and device capability |
| Battery | 3 | Core battery / ANC / EQ paths implemented; WF-1000XM4 core paths verified |
| Common | 10 | Protocol catalogue; implementation varies by typed handler and device capability |
| CommonCapability | 1 | Protocol catalogue; implementation varies by typed handler and device capability |
| Connect | 2 | Protocol catalogue; implementation varies by typed handler and device capability |
| ConnectionStatus | 1 | Protocol catalogue; implementation varies by typed handler and device capability |
| DeviceInfo | 4 | Protocol catalogue; implementation varies by typed handler and device capability |
| EqEbb | 16 | Core battery / ANC / EQ paths implemented; WF-1000XM4 core paths verified |
| Gs | 7 | Protocol catalogue; implementation varies by typed handler and device capability |
| LEA | 24 | Protocol catalogue; implementation varies by typed handler and device capability |
| LinkControl | 1 | Protocol catalogue; implementation varies by typed handler and device capability |
| Log | 4 | Protocol catalogue; implementation varies by typed handler and device capability |
| NcAsm | 17 | Core battery / ANC / EQ paths implemented; WF-1000XM4 core paths verified |
| Opt | 5 | Protocol catalogue; implementation varies by typed handler and device capability |
| Optimizer | 2 | Protocol catalogue; implementation varies by typed handler and device capability |
| Party | 6 | Protocol catalogue; implementation varies by typed handler and device capability |
| Peripheral | 5 | Protocol catalogue; implementation varies by typed handler and device capability |
| Play | 9 | Protocol catalogue; implementation varies by typed handler and device capability |
| Power | 19 | Core battery / ANC / EQ paths implemented; WF-1000XM4 core paths verified |
| PowerOff | 1 | Protocol catalogue; implementation varies by typed handler and device capability |
| SARAutoPlay | 6 | Protocol catalogue; implementation varies by typed handler and device capability |
| SafeListening | 6 | Protocol catalogue; implementation varies by typed handler and device capability |
| Sense | 3 | Protocol catalogue; implementation varies by typed handler and device capability |
| Sports | 1 | Protocol catalogue; implementation varies by typed handler and device capability |
| System | 41 | Protocol catalogue; implementation varies by typed handler and device capability |
| Update | 11 | Excluded: firmware updater |
| Updt | 9 | Excluded: firmware updater |
| VoiceGuidance | 10 | Protocol catalogue; implementation varies by typed handler and device capability |
| Vpt | 2 | Protocol catalogue; implementation varies by typed handler and device capability |

The app must select protocol version, table, advertised function, and availability before reading or writing a control. An ACK alone never proves a setting changed. Core readback fixtures come from WF-1000XM4 firmware 2.3.1; other models are untested.

Sony Account, cloud services, and firmware updating are excluded. Voice-assistant provider setup, Quick Access integrations, phone activity/location rules, audio rendering, and LE Audio profile management require additional host or service work. Hardware declarations for these remain catalogued so missing work is visible.

All inquiry rows begin as `catalogued_not_implemented`; only narrowly established core fields are marked hardware verified. New application handlers must be reported separately and tested before changing this status. See `DEVICE_SUPPORT.md` for the support boundary and `REVERSE_ENGINEERING.md` for evidence limitations.
