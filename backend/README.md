# Heartbeat Backend

## Run locally

```bash
cd backend
npm install
cp .env.example .env
npm run dev
```

Server runs on `http://localhost:4000` by default.

## API

- `POST /api/user/register`
- `POST /api/checkin`
- `GET /api/status/:userId`
- `POST /api/evaluate`

## Notes

- If user misses 2 or more days, `/api/evaluate` triggers emergency call logic.
- Current implementation simulates the call by logging to console.
- For production, replace `placeEmergencyCall` with Twilio or another voice provider.
