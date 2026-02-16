# 活这么 - Check-in Emergency App

## Structure

- `frontend/` iOS SwiftUI app source
- `backend/` Node.js local API server

## Backend quick start

```bash
cd backend
npm install
cp .env.example .env
npm run dev
```

## Frontend quick start

1. Open Xcode, create `HeartbeatApp` project.
2. Copy files from `frontend/HeartbeatApp/` into Xcode project.
3. Run iOS simulator/device.

## Important iOS limitation

iOS app cannot silently auto-dial phone calls in the background.
Automated emergency calling should be handled by backend telephony integration.
