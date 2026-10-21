# iOS setup and installation

## Requirements

- macOS with Xcode and the iOS SDK.
- Python 3 for catalog generation.
- A connected, trusted iPhone for physical deployment. Set `DEVICE_ID` and
  `DEVELOPMENT_TEAM` on the Make command line when the configured defaults do
  not match the current device/team.

## Build

Run `make catalog` after changing recipe source or parser code. Use
`make catalog-check` to verify the checked-in bundled JSON matches the source.
Use `make sim-build` for a simulator compile and `make sim-launch` for install
and launch on the named simulator. Use `make phone-build` for a signed device
build, then `make phone-install` and `make phone-launch`; `make phone-deploy`
combines those operations.

The app requests Reminders access only when a grocery list is needed. Photos are
selected through the system photo picker. The dinner planner can currently save
an offline estimated draft; AI schedule generation is not connected yet.
