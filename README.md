# L ScalpX backend

Real backend for your L ScalpX Bot PWA: login, live quotes (Twelve Data), a
real technical-analysis scanner, AI trade commentary (Claude, optional), and
MT5 sync via a companion Expert Advisor.

## What's real here vs. what you still need to add

| Piece | Status |
|---|---|
| Login / signup | Real (SQLite + bcrypt + JWT) |
| Face ID / fingerprint login | Real, via WebAuthn/passkeys — uses your device's actual secure hardware, backend never sees biometric data |
| Live quotes | Real, via Twelve Data — needs your API key |
| Scanner signals | Real math (SMA crossover + RSI) over live price history |
| AI chart scanner | Real Claude call reading actual OHLC candles for pattern/trend analysis, wired into the app's existing Structure tab |
| AI commentary | Real Claude call — needs your Anthropic API key, optional |
| MT5 sync | Real, via the included `LScalpXBridge.mq5` EA — needs you to attach it to a chart in your own MT5 terminal |

## 1. Local setup

```bash
npm install
cp .env.example .env
# edit .env: paste your Twelve Data key, set JWT_SECRET and EA_SHARED_SECRET
# to random strings, optionally paste an Anthropic key
npm start
```

Server runs on `http://localhost:8080` by default. Check `http://localhost:8080/api/health`.

## 2. Point the app at it

Open the L ScalpX app → Account → Backend Connection → paste your backend's
public URL (once deployed) → Save. Sign up for an account in the app itself.

## 3. Deploy somewhere public

Any Node host works. Two easy free-tier options:

- **Railway** (railway.app): New Project → Deploy from GitHub repo (push this
  folder to its own repo first) → add the same environment variables from
  `.env.example` in the Railway dashboard → it gives you a public URL.
- **Render** (render.com): New → Web Service → same idea, `npm install` as
  build command, `npm start` as start command.

Either way, **the app's data (`data.sqlite`) lives on the server's disk** —
that's fine for one user; if you want multiple people using this, swap
`better-sqlite3` for a hosted Postgres later (schema is simple enough to port).

## 4. Face ID / fingerprint login (WebAuthn)

1. Set `WEBAUTHN_RP_ID` to your backend's bare domain (e.g. `myapp.example.com`,
   no `https://`) and `WEBAUTHN_ORIGIN` to the full origin the **app itself**
   is served from. For a PWA opened at `https://myapp.example.com` these
   match; for the packaged Android app, this needs to be the https origin
   associated with your app via Digital Asset Links (the same domain your
   `assetlinks.json` already points at) — passkeys won't verify against an
   `android://` package name.
2. In the app: log in normally once with email/password, then go to
   Account → "Enable Face ID / Fingerprint on this device". This registers
   a passkey tied to your device's secure hardware.
3. From then on, the FINGERPRINT / FACE ID buttons on the login screen work
   for real — no password needed, and the backend never sees or stores any
   biometric data, only a public key.

## 5. AI chart scanner (real candle analysis)

Once `TWELVE_DATA_API_KEY` and `ANTHROPIC_API_KEY` are both set, the app's
existing Structure/AI tab automatically shows real output: `GET /api/mt5/status`
now attaches a `scan` object built from actual recent OHLC candles run through
both the SMA/RSI scanner and a Claude call that reads the candle shape itself
(trend, support/resistance being tested, obvious patterns) — no frontend
changes needed, it fills the same slot the app's demo data used to fill.

## 6. Get an Anthropic API key (for AI commentary — optional)

1. Go to console.anthropic.com and sign up
2. API Keys → Create Key
3. Paste it as `ANTHROPIC_API_KEY` in your `.env` / host's env vars
4. Leave it blank and everything else still works — you just get a plain
   templated sentence instead of an AI-written one.

## 7. Connect real MT5

1. In the app: Dashboard → MT5 Sync → fill in broker/server/login → Connect.
   This registers the account on the backend and shows you an `api_token` —
   you don't need that token for the EA below (it matches on MT5 login
   number instead), but keep it around for reference.
2. Open **MetaEditor** in your MT5 terminal, create a new Expert Advisor,
   paste in `LScalpXBridge.mq5` from this folder, compile it.
3. In MT5: Tools → Options → Expert Advisors → check "Allow WebRequest for
   listed URL" → add your deployed backend's URL.
4. Drag the compiled EA onto the chart for the **same symbol/timeframe** you
   configured in the app's Scanner screen. Fill in its inputs:
   - `BackendUrl` — your deployed backend URL
   - `EaSharedSecret` — must match `EA_SHARED_SECRET` in your `.env`
   - `Mt5LoginId` — must match the login you entered in step 1
5. The EA now heartbeats balance/equity, polls for scanner-queued trades,
   opens them for real, and reports fills back. **Start on a demo MT5
   account** until you've watched it behave the way you expect.

## Notes on the scanner logic

`src/services/scanner.js` is deliberately simple (SMA8/SMA21 crossover +
RSI14 filter) so it's easy to read and change. It is not investment advice
and isn't tuned for any particular market — treat it as a starting point,
backtest/paper-trade before risking real money, and keep `MAX TRADES` low
while you're testing.
