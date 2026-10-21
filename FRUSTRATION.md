# Frustration log

- 2026-10-21: `make sim-launch` built successfully, then failed because `open -a Simulator` could not resolve Simulator.app. Direct `xcrun simctl install` also failed after CoreSimulatorService became unavailable. Use `make sim-build` to verify compilation; simulator interaction remains unverified until Simulator.app and CoreSimulatorService are available.
