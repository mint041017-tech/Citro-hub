import { cp, mkdir, readdir, rm, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(fileURLToPath(import.meta.url));
const source = path.join(root, "site");
const output = path.join(root, "dist");
const requiredFiles = ["index.html", "styles.css", "app.js", "data.js", "favicon.svg"];

const sourceStat = await stat(source).catch(() => null);
if (!sourceStat || !sourceStat.isDirectory()) {
  console.error("Source folder not found: site/");
  process.exit(1);
}

const sourceFiles = await readdir(source);
const missing = requiredFiles.filter((file) => !sourceFiles.includes(file));
if (missing.length) {
  console.error("Missing required site files:", missing.join(", "));
  process.exit(1);
}

await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
for (const file of requiredFiles) {
  await cp(path.join(source, file), path.join(output, file));
}

console.log("Citro Analytics built to dist/");
console.log("Preview: python -m http.server 4173 --directory dist");
