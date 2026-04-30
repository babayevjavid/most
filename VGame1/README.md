# Realtime 4-Player Matchmaking Chat

FastAPI + WebSockets prototype with:

- Lobby queue broadcast (`1/4`, `2/4`, etc.)
- Auto-match when exactly 4 players are available
- Isolated per-room chat (messages go only to the other 3 users)
- Disconnect notification inside room
- Click-to-translate frontend mock (no LLM, deterministic placeholder)

## Run locally

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload
```

Open:

- http://127.0.0.1:8000

Open 4 tabs/devices to trigger matchmaking.

## Publish to GitHub

From this folder:

```bash
git add VGame1
git commit -m "Add realtime matchmaking chat prototype"
git push
```

If this folder is not yet in a remote repo, create one on GitHub first and then:

```bash
git remote add origin https://github.com/<your-username>/<your-repo>.git
git branch -M main
git push -u origin main
```

## Mobile testing from internet

GitHub Pages cannot run a FastAPI WebSocket backend, so deploy this as a web service:

### Option A (recommended): Render (Blueprint)

1. Push this repo to GitHub.
2. In Render, choose **New +** -> **Blueprint** and select your repo.
3. Render will read `render.yaml` and deploy automatically.
4. Open the generated `https://...onrender.com` URL on your phone.

Because frontend and WebSocket backend are served from same origin (`/` + `/ws`), it works on phone without extra config.
