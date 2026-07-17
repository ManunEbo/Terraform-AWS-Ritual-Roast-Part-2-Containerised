# V2 Frontend — Vite + React

This is the "challenger" frontend for Ritual Roast: the same recipe-contest page as
`apps/v1-frontend-nextjs`, deliberately rebuilt as a plain client-side single-page app with
Vite + React, served by nginx. It exists to give the canary/blue-green/shadow-traffic exercises in
`infrastructure/05-aws-k8s` a genuinely different second version to route traffic to — different
build tool, different rendering model, different backend language on the other end
(`apps/v2-backend-go`) — while doing the same job for the same users.

It's also styled on purpose to look completely different from v1 — a dark, neon "telemetry" theme
rather than v1's warm bakery branding — so that during a live demo, *which version is currently being
served* is obvious at a glance, no dev tools required. More on that below.

## What's in this directory

| Path | Purpose |
|---|---|
| `src/main.jsx` / `src/App.jsx` | Entry point and the top-level component; fetches recipes client-side. |
| `src/recipeService.js` | Plain `fetch()` calls to the backend, relative to whatever origin served the page. |
| `src/components/RecipeForm.jsx` | The submission form. |
| `src/components/RecipeTable.jsx` | Renders the fetched recipes. |
| `nginx.conf` | The production web server config — serves the built static files **and** reverse-proxies `/api/*` to the backend. |
| `vite.config.js` | Build tooling config, including a *local-only* dev proxy. |
| `Dockerfile` | Two-stage build: compile with Node, serve with nginx. |

## The rendering model: fetch after mount, not before

Unlike v1, there's no server here to pre-fetch anything — this is a plain single-page app, so data
has to be fetched from inside the browser, after the page has already loaded:

```jsx
function App() {
  const [recipes, setRecipes] = useState([]);
  const [loading, setLoading] = useState(true);

  const fetchDatabase = async () => {
    setLoading(true);
    const data = await getRecipes();
    setRecipes(data);
    setLoading(false);
  };

  useEffect(() => { fetchDatabase(); }, []);

  return loading
    ? <div>SYNCING WITH V2 BACKEND...</div>
    : <RecipeTable initialRecipes={recipes} />;
}
```

This is the direct trade-off against v1's server-first approach: v1 never shows a loading state
because the data is already embedded in the HTML by the time it arrives; this app always shows one
briefly, because the browser has to make a round trip after the page is already visible. Neither is
a bug — it's the whole point of running both side by side, and it's a fair, honest comparison: a
Vite SPA is simpler to reason about and has no server runtime to operate at all, at the cost of that
initial fetch flash.

One place v2 is arguably *nicer* than v1: after a successful submission, `RecipeForm` calls
`onRecipeSubmitted`, which re-runs `fetchDatabase()` — a normal client-side re-fetch that updates the
table in place. v1, by contrast, does a full `window.location.reload()`. Both get you correct data;
v2's is the smoother interaction, v1's is the simpler code path.

## Walking through the app

### 1. `recipeService.js` — talking to the backend through a relative path

```javascript
const API_BASE = '/api';

export async function getRecipes() {
  const res = await fetch(`${API_BASE}/get_recipe`, { headers: { 'Accept': 'application/json' } });
  if (!res.ok) throw new Error(`Server Error: ${res.status}`);
  const data = await res.json();
  return Array.isArray(data) ? data : [];
}
```

Notice this never mentions a backend hostname anywhere — it just calls `/api/get_recipe`, relative to
whatever origin actually served this page. That's deliberate: this file has no idea whether it's
running behind nginx in production or Vite's dev server locally, and it doesn't need to. Whoever is
serving the page is also responsible for making `/api/*` reach the real backend (see `nginx.conf`
and `vite.config.js` below) — the frontend code itself stays identical either way.

This is noticeably simpler than v1's `recipeService.ts`: there's no `'use server'` boundary to cross
(a plain SPA has no server half to run on), and — worth calling out honestly rather than glossing
over — no `AbortController` timeout the way v1 defends against a hung backend. If the backend stalls
here, the fetch just waits.

### 2. `RecipeForm.jsx` — a conventional controlled form

```jsx
const handleSubmit = async (e) => {
  e.preventDefault();
  setIsSubmitting(true);
  const formData = new FormData(e.target);
  const result = await addRecipe(formData);
  if (result.success) {
    e.target.reset();
    if (onRecipeSubmitted) onRecipeSubmitted();
  }
  setIsSubmitting(false);
};
```

No client-side validation library or floating-label inputs here — uses plain HTML5 `required`
attributes on each field and lets the browser handle it. `new FormData(e.target)` reads the form
directly from the DOM rather than tracking every field in React state, which is less code for a form
this size, at the cost of not being able to show inline per-field errors the way v1's version does.

### 3. `nginx.conf` — one file doing two jobs

```nginx
server {
    listen 3000;

    location / {
        root   /usr/share/nginx/html;
        try_files $uri $uri/ /index.html;
        add_header Set-Cookie "x-frontend=v2; Path=/; SameSite=Lax" always;
    }

    location /api/ {
        proxy_pass http://ritual-roast-backend:5000/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

- **`listen 3000`** — deliberately matches the port v1's Next.js server listens on, so a single
  Kubernetes Service (targeting port 3000) can front either version's pods interchangeably; only the
  pod label (`version: v1` / `version: v2`) changes which one actually receives traffic.
- **`try_files $uri $uri/ /index.html`** — the standard SPA fallback: any path that isn't a real
  static file falls through to `index.html` so client-side routing (if this app ever grows real
  routes) doesn't 404 on a refresh.
- **`add_header ... always`** — sets the same kind of canary session cookie v1 sets
  (`x-frontend=v2` here, vs. v1's `x-frontend=v1`), with the same attributes, so Istio's
  `frontend` VirtualService (`infrastructure/05-aws-k8s`) can pin a browser session to whichever
  version it first landed on. The `always` flag matters — without it, nginx only adds custom headers
  to "successful" response codes, and static asset responses (cached 304s, etc.) could otherwise skip
  the cookie and desync the session's pinned version from its actual asset tree.
- **`location /api/` — the interesting part.** This proxies to `http://ritual-roast-backend:5000`,
  which is a **Kubernetes Service DNS name**, not a configurable environment variable the way v1's
  `BACKEND_URL` is. That's a real difference between the two frontends, not an oversight: v1 was
  built to be portable between ECS and Kubernetes (its backend address is injected at deploy time
  either way), while v2 was purpose-built for the Istio/Kubernetes canary environment and never needs
  to run anywhere else — so it can bake in a Kubernetes-native service name directly. Because this
  request still passes back out through the pod's Istio sidecar, the **backend** VirtualService's
  traffic weight still applies to it exactly as it would to any other call to that service — a
  request that started at a v2 frontend pod can still be routed to either the v1 or v2 *backend*,
  independently of which frontend served the page. Frontend and backend traffic splits are two
  separate dials.

### 4. `vite.config.js` — a second, local-only proxy

```javascript
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    proxy: { '/api': { target: 'http://localhost:5000', changeOrigin: true } }
  }
})
```

This proxy only exists for `npm run dev` — Vite's own dev server, run directly on a laptop, has
nothing like nginx in front of it, so this recreates the same "`/api` reaches the backend" behaviour
for local development, pointed at a backend running on `localhost:5000`. It has no effect on the
production build; `nginx.conf` is what actually runs in the container.

## The "cyberpunk telemetry" theme — a deliberate demo tool, not a style accident

Compare v1's warm bakery-brand palette (browns and gold, "Add your Recipe") against this app's dark
background, neon-green accents, and copy like *"SYNCING WITH V2 BACKEND..."*, *"Telemetry Log"*, and
column headers reading `CHEF / DESIGNATION / COMPONENTS / PROTOCOL` instead of
`Name / Recipe / Ingredients / Description`. This is intentional, and it earns its keep during a
canary walkthrough: when traffic is being shifted live between v1 and v2 (10% → 50% → 90% → 100%),
being able to tell which version rendered a given browser tab **on sight** — without opening network
tools or reading cookies — makes the whole exercise demonstrable to a non-technical audience watching
over your shoulder, not just provable in Kiali's mesh graph.

## The Dockerfile

```dockerfile
FROM node:20-alpine AS builder
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
RUN rm -rf /usr/share/nginx/html/*
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 3000
CMD ["nginx", "-g", "daemon off;"]
```

Two stages: **Node** builds the static bundle (`vite build` → `dist/`), and a clean **nginx:alpine**
image serves it — the final image contains no Node runtime, no `node_modules`, and no source files
at all, only compiled HTML/JS/CSS and the nginx config. `daemon off` keeps nginx running in the
foreground so the container runtime (Kubernetes, here) can see it as the main process and correctly
detect if it dies.

## `package.json` at a glance

React 19 and Vite 5, styled with Tailwind CSS 4 — versioned independently as
`ritual-roast-v2-frontend@2.0.0` to make clear this is a distinct application, not a fork of v1's
`package.json` history.

## Where this fits in the bigger picture

This frontend only ever runs on `infrastructure/05-aws-k8s`, paired with `apps/v2-backend-go` — it
was purpose-built for the Istio canary/blue-green/shadow exercises and, unlike v1, was never deployed
to `infrastructure/04-aws-ecs`. See `infrastructure/05-aws-k8s/README.md` for how the two frontend
versions are actually split by Istio traffic weights, and how the `x-frontend` cookie keeps a given
browser session's static assets and canary version coherent for the duration of that session.
