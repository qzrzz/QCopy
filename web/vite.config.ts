import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

/** 构建纯 Vite React SPA 官网。 */
export default defineConfig({
  base: "./",
  build: {
    assetsInlineLimit: 0,
  },
  plugins: [react()],
});
