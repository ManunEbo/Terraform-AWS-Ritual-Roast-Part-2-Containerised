# V1 Frontend — Next.js

This is the original ("v1") frontend for Ritual Roast: the public-facing website visitors actually see — a recipe-contest landing page with a banner, a countdown timer, a submission form, and a table of submitted recipes. It's built with Next.js (React) using the **App Router**, and it never talks to the MySQL database itself; every piece of data goes through the Flask backend in
`apps/v1-backend-flask`.

Think of the backend as the kitchen and this as the dining room: the frontend's job is presentation and taking orders (recipe submissions), not touching the database directly.

## What's in this directory

| Path                                                               | Purpose                                                                                                          |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| `src/app/layout.tsx`                                               | The shared page shell — fonts, header, footer — wrapping every route.                                            |
| `src/app/page.tsx`                                                 | The home page. A Server Component that fetches recipes before the page is sent to the browser.                   |
| `src/app/components/recipeService.ts`                              | Server Actions — the only code in this app that talks to the Flask backend.                                      |
| `src/app/components/RecipeForm.tsx`                                | The client-side submission form.                                                                                 |
| `src/app/components/RecipeTable.tsx`                               | Renders the fetched recipes (desktop table + mobile card view).                                                  |
| `src/app/components/{Banner,Header,CountdownTimer,OurChoices}.tsx` | Presentational / marketing components.                                                                           |
| `src/app/api/health/route.ts`                                      | The shallow health-check endpoint.                                                                               |
| `next.config.ts`                                                   | Build-time configuration: the frozen contest deadline, a lean Docker output mode, and the canary session cookie. |
| `Dockerfile`                                                       | Multi-stage build producing a small, non-root production image.                                                  |

## The rendering model: fetch on the server, act on the server

Next.js's App Router defaults every component to a **Server Component** — it runs only on the
server and ships zero JavaScript to the browser for that component. `page.tsx` uses this directly:

```tsx
export default async function Home() {
	const recipes = await getRecipes(); // runs on the server, before any HTML is sent
	return (
		<main>
			<Banner />
			<CountdownTimer />
			<RecipeForm />
			<RecipeTable initialRecipes={recipes} />
			<OurChoices />
		</main>
	);
}
```

Because `Home` is declared `async` and awaits `getRecipes()` _before_ returning JSX, the recipes are already embedded in the HTML by the time it reaches the browser — there's no client-side loading spinner, no "fetch after mount" flash of empty content. Compare this with the v2 frontend (`apps/v2-frontend-vite`), which is a plain single-page React app and _has_ to fetch client-side after the page loads, because there's no server to do it for. Neither approach is wrong — they're just different points on the same tradeoff, which is rather the point of running both side by side.

```
Browser
   │  GET /
   ▼
Next.js server (page.tsx, a Server Component)
   │  await getRecipes()  — runs INSIDE the server, in the private network
   ▼
recipeService.ts  ('use server')
   │  fetch(BACKEND_URL + '/api/get_recipe')
   ▼
Flask backend  (never reachable from the browser directly)
   │
   ▼
RDS MySQL
```

The submission form works the same way in reverse — see `RecipeForm.tsx` below.

---

## Walking through the app

### 1. `recipeService.ts` — Server Actions as a secure proxy

```typescript
"use server";

const BACKEND_URL = process.env.BACKEND_URL || "http://localhost:5000";

export async function getRecipes(): Promise<Recipe[]> {
	try {
		const controller = new AbortController();
		const timeoutId = setTimeout(() => controller.abort(), 10000);

		const res = await fetch(`${BACKEND_URL}/api/get_recipe`, {
			signal: controller.signal,
			cache: "no-store",
			headers: { "Content-Type": "application/json", Accept: "application/json" },
		});
		clearTimeout(timeoutId);

		if (!res.ok) throw new Error(`Flask Server Error: ${res.status} ${res.statusText}`);
		const data = await res.json();
		return Array.isArray(data)
			? data
			: (() => {
					throw new Error("Invalid data format");
				})();
	} catch (err) {
		console.error("❌ Error fetching data from Flask:", err);
		return []; // graceful degradation — the page still renders
	}
}
```

The `'use server'` directive at the top of the file is what makes this a **Server Action**: every function exported from this file is guaranteed to run only on the server, never in the browser bundle. That matters here for a concrete reason — `BACKEND_URL` points at an address that is _only_ reachable from inside the private network (an internal ALB DNS name on ECS, or a cluster-internal Service name like `http://ritual-roast-backend:5000` on Kubernetes). If this fetch call lived in a
Client Component instead, the browser would need to resolve and reach that address directly, which it can't (and shouldn't be able to) — it's not exposed to the internet. Using a Server Action means the browser never even learns the backend's address exists; it just calls a function, and Next.js handles the server round-trip.

A few deliberate details:

- **`cache: 'no-store'`** — recipes are opted out of Next.js's data cache entirely, so every page load shows the current contents of the database, not a stale snapshot.
- **The `AbortController` with a 10-second timeout** — if the backend hangs (say, its own database connection is stuck), this request gives up after 10 seconds instead of leaving the whole page load hanging indefinitely.
- **Graceful degradation on any failure** — a network error, a timeout, or a malformed response all fall through to `return []`. The page still renders (with the "No Recipes Yet" empty state — see `RecipeTable.tsx`) instead of crashing the entire app with an unhandled 500. A user visiting during a backend blip sees an empty table, not a broken site.

`addRecipe` is the mirror image for writes:

```typescript
export async function addRecipe(formData: FormData): Promise<{ success: boolean; error?: string }> {
	const newRecipe = {
		name: formData.get("name") as string,
		email: formData.get("email") as string,
		recipe_name: formData.get("recipe_name") as string,
		ingredients: formData.get("ingredients") as string,
		description_main: formData.get("description_main") as string,
	};
	const res = await fetch(`${BACKEND_URL}/api/add_recipe`, {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify(newRecipe),
	});
	if (!res.ok) throw new Error(`Failed to add recipe: ${res.statusText}`);
	return { success: true };
}
```

It takes a `FormData` object, reshapes it into the JSON body Flask expects (matching the exact keys `app.py`'s `/api/add_recipe` route reads), and returns a plain `{success, error}` object rather than throwing an error; so the calling component can show a friendly message instead of an unhandled exception.

### 2. `RecipeForm.tsx` — a client component that calls the server directly

```tsx
"use client";
import { addRecipe } from "./recipeService";

const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
	e.preventDefault();
	const serverPayload = new FormData();
	serverPayload.append("name", formData.name.trim());
	// ...
	const result = await addRecipe(serverPayload);
	if (result.success) {
		alert("Recipe submitted successfully!");
		setTimeout(() => window.location.reload(), 1000);
	}
};
```

This is a **Client Component** (`"use client"` it needs `useState` for the form fields and focus handling, so it has to run in the browser). Notice there's no `fetch()` anywhere in this file: it imports `addRecipe`, a function whose actual body runs on the server and calls it like any other async function. Next.js compiles this into the network call under the hood.

From the developer's point of view, a Client Component invoking a Server Action reads exactly like a normal function call, with none of the manual; build, fetch, handle the response, parse the JSON; boilerplate the v2 frontend has to write by hand in `recipeService.js`.

Client-side validation (non-empty fields, a basic email regex) runs before the server call, purely to give the user immediate feedback — the actual source of truth for "is this data acceptable" is still the backend, which doesn't trust this validation either.

After a successful submission, the form reloads the whole page a second later (`window.location.reload()`) rather than trying to patch the recipe table in place. That's a deliberate simplicity trade: a full reload re-runs `page.tsx`'s server-side `getRecipes()` call, so the new recipe is guaranteed to appear exactly as the database now has it — no separate client-side cache-invalidation logic to keep in sync.

### 3. `RecipeTable.tsx` — rendering what the server already fetched

`RecipeTable` is a **Server Component** that receives `initialRecipes` as a prop from `page.tsx`, it does no fetching of its own. It handles the empty-database case explicitly:

```tsx
if (!initialRecipes || initialRecipes.length === 0) {
  return ( /* "No Recipes Yet" placeholder */ );
}
```

and renders two layouts from the same data — a full table for desktop (`hidden md:block`) and a stacked card view for mobile (`md:hidden`) — rather than relying on the table alone to reflow, which tends to become unreadable on narrow screens.

### 4. `src/app/api/health/route.ts` — the shallow health check

```typescript
export async function GET() {
	return NextResponse.json({ status: "ok", tier: "frontend" }, { status: 200 });
}
```

This is intentionally the simplest route in the app: it proves the Next.js server process is up and answering HTTP requests, and nothing more — it does **not** call the Flask backend or touch the database. That matters because this endpoint is wired as both the liveness _and_ readiness check on whichever platform is running the container (ECS target-group health check, or a Kubernetes probe).

If it did check the backend and the backend was momentarily unreachable, the platform would decide the frontend itself was broken and restart it — even though the frontend was perfectly healthy and the backend would have recovered on its own. See `apps/v1-backend-flask`'s README for the full "shallow vs. deep health check" reasoning, and `apps/v2-backend-go`'s README for why the Go backend needs a second separate shallow endpoint to follow the same rule.

### 5. `next.config.ts` — three small decisions with outsized consequences

```typescript
const CONTEST_DEADLINE = process.env.NEXT_PUBLIC_CONTEST_DEADLINE
	? new Date(process.env.NEXT_PUBLIC_CONTEST_DEADLINE)
	: new Date("2026-09-29T00:00:00Z");

const nextConfig: NextConfig = {
	env: { NEXT_PUBLIC_CONTEST_DEADLINE: CONTEST_DEADLINE.toISOString() },
	output: "standalone",
	typescript: { ignoreBuildErrors: false },
	async headers() {
		return [
			{
				source: "/:path*",
				headers: [{ key: "Set-Cookie", value: "x-frontend=v1; Path=/; SameSite=Lax" }],
			},
		];
	},
};
```

- **A frozen deadline, not a rolling one.** Under this project's GitOps model, every commit to `apps/**` triggers a fresh image build tagged with that commit's SHA (see `infrastructure/05-aws-k8s/README.md` for the full pipeline). If `CountdownTimer.tsx` computed "three months from now" at build time, every single rebuild including ones that have nothing to do with the contest — would silently push the deadline further into the future. Baking in a fixed ISO date (overridable via an env var for local testing) means the countdown means the same thing no matter how many times the image gets rebuilt.
- **`output: 'standalone'`.** A default Next.js production build expects the entire `node_modules` tree to sit alongside it at runtime, heavy and mostly unused. Standalone mode traces the actual runtime dependency graph and copies only what's needed into `.next/standalone`, which is what lets the final Docker image (below) be lean.
- **The `x-frontend=v1` cookie.** This is the detail that ties this app into the wider canary infrastructure. Every response from this frontend stamps a session cookie identifying it as v1. Istio's `frontend` VirtualService (in `infrastructure/05-aws-k8s`) matches on that cookie before falling through to the weighted canary split — so once a browser session lands on v1, it stays on v1 for the rest of the session, rather than potentially being routed to a different version's `/_next/static/*` assets on a later request (which would break the page). The v2 frontend (`apps/v2-frontend-vite`) sets the equivalent `x-frontend=v2` cookie with identical attributes, so the pair behaves symmetrically regardless of which version a session first lands on.

---

## The Dockerfile: three stages, one lean runtime image

```dockerfile
FROM node:20-alpine AS deps
COPY package.json package-lock.json ./
RUN npm ci
```

**Stage 1** installs dependencies from the committed lockfile only (`npm ci`, not `npm install`), a deterministic install that fails loudly if `package-lock.json` and `package.json` disagree, rather than silently resolving something different from what was tested.

```dockerfile
FROM node:20-alpine AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build
```

**Stage 2** builds the app. This is where `npm run build` runs ESLint, type-checks (the build fails on a TypeScript error, see `typescript.ignoreBuildErrors: false` above), and locks in the contest deadline from the previous section.

```dockerfile
FROM node:20-alpine AS runner
RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nextjs
COPY --from=builder /app/public ./public
RUN mkdir .next && chown nextjs:nodejs .next
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3000
ENV HOSTNAME="0.0.0.0"
CMD ["node", "server.js"]
```

**Stage 3** is the image that actually ships. Only three things are copied in: the static `public/` folder, the standalone server bundle, and its static assets, no `node_modules`, no source `.tsx` files, no build cache. The process runs as a dedicated non-root `nextjs` user, and `ENV HOSTNAME="0.0.0.0"` is not optional: without it, Node's default server binds to `localhost` only, which would make the container unreachable from an internal ALB or a Kubernetes Service — both of which connect from a different network namespace, not `localhost`.

## `package.json` at a glance

Next.js 15 on React 19, styled with Tailwind CSS 4. Nothing unusual here beyond the versions being current at time of writing — the interesting engineering is in `next.config.ts` and `recipeService.ts` above, not in the dependency list.

## The presentation layer

`Banner`, `Header`, `CountdownTimer`, and `OurChoices` are the marketing/UI components, a hero image, a responsive nav with a mobile slide-out menu, a live countdown built with `setInterval` and a hydration guard (it renders an empty placeholder until the component has mounted on the client, to avoid the server-rendered and client-rendered clocks ever visibly disagreeing), and a simple photo grid. None of them talk to the backend; they exist to make the contest page feel like a real product rather than a bare data table.

## Where this fits in the bigger picture

This is the **v1 / baseline** half of a frontend comparison: `apps/v2-frontend-vite` is a client-side-rendered rewrite of the same page, built to see how a simpler SPA compares against Next.js's server-first approach under Istio traffic-shifting. The exact same container image built from this directory runs on **both** `infrastructure/04-aws-ecs` (Fargate, behind an internal ALB) and `infrastructure/05-aws-k8s` (a Kubernetes Deployment behind an Istio-meshed Service) — never at
the same time. See `infrastructure/05-aws-k8s/README.md` for how traffic is actually split between the v1 and v2 frontends during the canary / blue-green / shadow exercises.
