// Refresh the self-contained cleanup skill from npm ci's pinned yaml package.
// Run npm --prefix setup run vendor:cleanup-yaml to refresh, or add -- --check
// to compare the checked-in runtime with the installed package.
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const setup = path.dirname(fileURLToPath(import.meta.url));
const source = path.join(setup, "node_modules", "yaml");
const target = path.resolve(setup, "../skills/local/worktree-runtime-cleanup/vendor/yaml");
const check = process.argv[2] === "--check";
if (process.argv.length > (check ? 3 : 2)) throw new Error("usage: node sync-cleanup-yaml.mjs [--check]");

async function files(root, relative = "") {
  const entries = await readdir(path.join(root, relative), { withFileTypes: true });
  const children = [];
  for (const entry of entries) {
    const child = path.join(relative, entry.name);
    if (entry.isDirectory()) children.push(...await files(root, child));
    else if (entry.isFile()) children.push(child);
    else throw new Error("unexpected non-regular package entry: " + child);
  }
  return children.sort();
}

const readJson = async (file) => JSON.parse(await readFile(file, "utf8"));
const pkg = await readJson(path.join(source, "package.json"));
const lock = await readJson(path.join(setup, "package-lock.json"));
if (pkg.name !== "yaml" || pkg.version !== lock.packages["node_modules/yaml"].version ||
    pkg.type !== "commonjs" || pkg.main !== "./dist/index.js" ||
    Object.keys(pkg.dependencies ?? {}).length > 0) {
  throw new Error("installed YAML package does not match the pinned self-contained Node runtime");
}

const manifest = { private: true, name: pkg.name, version: pkg.version, license: pkg.license, type: pkg.type, main: pkg.main };
const extraEntrypoints = new Set(["test-events.js", "util.js"]);
const runtime = (await files(source, "dist")).filter((file) => file.endsWith(".js") && !extraEntrypoints.has(path.basename(file)));
const expected = new Map([["package.json", Buffer.from(JSON.stringify(manifest, null, 2) + "\n")]]);
for (const file of ["LICENSE", ...runtime]) {
  expected.set(file, await readFile(path.join(source, file)));
}
for (const [file, contents] of expected) {
  const destination = path.join(target, file);
  if (check) {
    if (!contents.equals(await readFile(destination))) throw new Error("generated YAML runtime differs: " + file);
  } else {
    await mkdir(path.dirname(destination), { recursive: true });
    await writeFile(destination, contents);
  }
}
for (const file of await files(target)) {
  if (!expected.has(file)) throw new Error("unexpected file in generated YAML runtime: " + file);
}
