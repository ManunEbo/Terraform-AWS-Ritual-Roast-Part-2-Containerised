import { dirname } from "path";
import { fileURLToPath } from "url";
import { FlatCompat } from "@eslint/eslintrc";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const compat = new FlatCompat({
  baseDirectory: __dirname,
});

const eslintConfig = [
  ...compat.extends("next/core-web-vitals", "next/typescript"),
  {
    // Custom Rules for Ritual Roast "Masterpiece" Quality
    rules: {
      // 1. Prevent unused variables from cluttering the build
      "@typescript-eslint/no-unused-vars": ["warn", { "argsIgnorePattern": "^_" }],
      
      // 2. Ensure hooks (useEffect, useCallback) have all dependencies
      "react-hooks/exhaustive-deps": "warn",
      
      // 3. Prevent the use of 'any' which bypasses TypeScript's safety
      "@typescript-eslint/no-explicit-any": "warn",
      
      // 4. Disallow console.logs in production to keep the browser console clean
      "no-console": ["warn", { "allow": ["warn", "error"] }],
      
      // 5. Enforce better accessibility for the Recipe Table and images
      "jsx-a11y/alt-text": "error",
      
      // 6. Prevent unescaped entities (fixes the &apos; issues we saw in Banner)
      "react/no-unescaped-entities": "error"
    }
  }
];

export default eslintConfig;