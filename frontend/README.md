# Heartbeat iOS Frontend (SwiftUI)

## Current state

This folder includes complete Swift source files for a simple iOS app:
- Center red heart UI
- Manual daily check-in button
- Emergency contact form
- Calls backend APIs for register/check-in/evaluate

## Create Xcode project

1. Open Xcode and create a new **App** project named `HeartbeatApp`.
2. Replace generated Swift files with files from `frontend/HeartbeatApp/`.
3. Ensure deployment target is iOS 16+ (or adjust as needed).
4. Set app icon images in `Assets.xcassets/AppIcon.appiconset`.

## Backend URL

Default is `http://127.0.0.1:4000`.
Use your Mac local IP when testing on a real iPhone.
