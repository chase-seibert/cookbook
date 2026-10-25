# Frustration log

- 2026-10-21: `make sim-launch` built successfully, then failed because `open -a Simulator` could not resolve Simulator.app. Direct `xcrun simctl install` also failed after CoreSimulatorService became unavailable. Use `make sim-build` to verify compilation; simulator interaction remains unverified until Simulator.app and CoreSimulatorService are available.
- 2026-10-24: The same missing `Simulator.app` made `make sim-launch` stop after a successful build. With host access, `simctl` still booted, installed, and launched the app; `simctl screenshot` confirmed the recipe images in grid mode. Use the explicit `-browseMode grid` launch argument to inspect tiles without persisting the user's browse preference.
