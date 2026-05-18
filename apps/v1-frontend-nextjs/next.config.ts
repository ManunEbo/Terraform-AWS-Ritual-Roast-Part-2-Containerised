import type { NextConfig } from "next";

// Calculate exactly 3 months from the moment the Docker build happens
const deploymentDeadline = new Date();
deploymentDeadline.setMonth(deploymentDeadline.getMonth() + 3);
deploymentDeadline.setHours(15, 0, 0, 0);

const nextConfig: NextConfig = {
  // 1. Bake the deployment date permanently into the build for the CountdownTimer
  env: {
    NEXT_PUBLIC_CONTEST_DEADLINE: deploymentDeadline.toISOString(),
  },
  
  // 2. By default, a Next.js build is bloated. 
  // This is the professional production fix (makes the Fargate container lean).
  output: 'standalone', 
  
  // 3. Keep this false to ensure code quality
  typescript: {
    ignoreBuildErrors: false, 
  }
};

export default nextConfig;