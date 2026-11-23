# Grocery-list crash log capture

## User requirements

- As a user, I want the crash reports from my iPhone captured for the intermittent grocery-list add crash, so that the failure can be diagnosed from its timestamp, exception, and stack trace.
- As a user, I want the log capture to preserve the original report and identify the app version and reproduction steps, so that a crash can be compared with a successful add attempt.
- Assumption: this task is to collect and inspect device crash logs first. It does not authorize a code fix, persistent telemetry, or changes to grocery-list behavior.

## Architecture and data model

The grocery review flow is implemented in `ios/Cookbook/CookingAndGroceries.swift` (`GroceryReviewView`). It reads and writes the selected Reminders list through EventKit, then records a completed grocery flow in the existing SwiftData usage store after a successful commit. Device crash reports are produced by iOS and retrieved through Xcode/device diagnostics; the app has no crash-log export subsystem. No material architecture, persistence, schema, or migration change is required for this diagnostic task.

## Basic test cases

- With the iPhone connected, trusted, and unlocked, open its device logs in Xcode and confirm a Cookbook crash report can be exported or that the available report list has been checked for the relevant time window.
- Record the installed app version/build and the local time of one controlled grocery-add attempt. If it crashes, confirm the exported `.ips` report names the Cookbook process and has a matching timestamp; retain the raw report if symbolication is unavailable.
- If the attempt succeeds, confirm selected items appear once in the chosen Reminders list and record that outcome and time alongside the crash search window.
- If no matching report exists, check iPhone Analytics Data or the device's available diagnostic reports and record whether the attempt was reproduced, rather than treating absence of a report as proof that no crash occurred.
- For a partial or failed add, verify the existing “Check Reminders before retrying” message is observed and inspect the list before another attempt to avoid mistaking duplicate reminders for a successful reproduction.

## High-level implementation details

1. Confirm the target iPhone is available to Xcode; note the Cookbook version/build, iOS version, and current time. Use Xcode's Devices and Simulators device logs to locate and export Cookbook crash reports for the incident window. If the report is missing there, check the iPhone's Analytics Data as a fallback.
2. Keep the original crash report unchanged. Record its filename, timestamp, exception/termination reason, crashed thread, and whether symbols resolve to app frames. Redact personal data before sharing a copy outside the diagnostic workspace.
3. If a matching report is not already present, perform one controlled reproduction using a test Reminders list and a small, known selection. Record the list, selection, app build, exact time, and whether the app crashed or committed the reminders; check the list before retrying after a partial result.
4. Correlate the report with the grocery path in `GroceryReviewView`, especially EventKit list access, asynchronous reminder fetching and main-thread state updates, per-reminder saves, the batch commit, and the post-commit usage update. Treat the stack trace as evidence before proposing any code change.
5. Report whether a matching crash log was captured and what diagnostic evidence it contains. If the phone is unavailable, the report has aged out, or symbols are missing, state that limitation and preserve the raw report or reproduction notes for a follow-up diagnosis. No app build is needed unless a later, separately scoped code change is made.
