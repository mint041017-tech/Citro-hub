import { copyFile, cp, mkdir, rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(fileURLToPath(import.meta.url));
const dist = path.join(root, "dist");
const files = ["index.html", "styles.css", "app.js", "manifest.webmanifest"];

await rm(dist, { recursive: true, force: true });
await mkdir(dist, { recursive: true });

for (const file of files) {
  await copyFile(path.join(root, file), path.join(dist, file));
}

await cp(path.join(root, "assets"), path.join(dist, "assets"), { recursive: true });

console.log(`Built ${path.relative(process.cwd(), dist)}`);
