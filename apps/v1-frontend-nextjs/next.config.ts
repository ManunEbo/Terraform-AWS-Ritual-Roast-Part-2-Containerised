import type { NextConfig } from "next";

// Fixed contest deadline. Under the SHA-promotion model every rebuild would
// otherwise push a dynamic countdown forward, so pin it (env-overridable).
const CONTEST_DEADLINE = process.env.NEXT_PUBLIC_CONTEST_DEADLINE
  ? new Date(process.env.NEXT_PUBLIC_CONTEST_DEADLINE)
  : new Date('2026-09-29T00:00:00Z');

const nextConfig: NextConfig = {
  // 1. Bake the deployment date permanently into the build for the CountdownTimer
  env: {
    NEXT_PUBLIC_CONTEST_DEADLINE: CONTEST_DEADLINE.toISOString(),
  },

  // 2. By default, a Next.js build is bloated.
  // This is the professional production fix (makes the Fargate container lean).
  output: 'standalone',

  // 3. Keep this false to ensure code quality
  typescript: {
    ignoreBuildErrors: false,
  },

  // 4. D5 - frontend version stickiness for the Istio canary.
  //    This image IS v1 (Next.js), so it stamps every response with
  //    x-frontend=v1. Istio's frontend VirtualService matches this cookie
  //    BEFORE the weighted entry, pinning the whole session to the v1
  //    subset so the /_next/static/* asset tree stays coherent.
  //
  //    - Session cookie (no Max-Age): stickiness lasts the browser
  //      session; a fresh session re-rolls against the canary weight.
  //    - Path=/ + SameSite=Lax: matches the Vite (v2) cookie attributes
  //      so both halves of the pair behave identically. All requests are
  //      first-party to the ALB origin, so Lax still sends the cookie on
  //      asset and /api subrequests.
  //    - Compatible with output:'standalone' - the standalone node server
  //      applies headers() exactly like a normal build, and Envoy passes
  //      upstream Set-Cookie headers through to the browser unchanged.
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          {
            key: 'Set-Cookie',
            value: 'x-frontend=v1; Path=/; SameSite=Lax',
          },
        ],
      },
    ];
  },
};

export default nextConfig;
