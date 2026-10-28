import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";

export type SharedLink = { name: string; source: string; directory?: boolean };
export type Snapshot = Record<string, string>;
export type SharedChange = SharedLink & { before?: Snapshot; markerBefore?: string; copy?: boolean };

export function copyMarker(name: string): string {
  return path.join(path.dirname(name), `.dotfiles-copy-${path.basename(name)}.json`);
}

// Content fingerprints include empty directories and binary supporting files.
// Only source trees may contain symlinks; an installed copy must be independent.
export function snapshot(file: string, source = false): Snapshot | undefined {
  if (!fs.lstatSync(file, { throwIfNoEntry: false })) return undefined;
  const result: Snapshot = Object.create(null);
  const visit = (current: string, name: string, ancestors: Set<string>) => {
    const stat = fs.lstatSync(current);
    if (stat.isSymbolicLink() && !source) throw new Error(`Unexpected link in shared copy: ${name}`);
    const real = fs.realpathSync(current);
    if (ancestors.has(real)) throw new Error(`Cyclic shared source: ${name}`);
    if (fs.statSync(current).isDirectory()) {
      result[name] = "directory";
      const next = new Set([...ancestors, real]);
      for (const child of fs.readdirSync(current).sort()) visit(path.join(current, child), name === "." ? child : `${name}/${child}`, next);
    } else if (fs.statSync(current).isFile()) {
      result[name] = createHash("sha256").update(fs.readFileSync(current)).digest("hex");
    } else throw new Error(`Unexpected shared entry: ${name}`);
  };
  visit(file, ".", new Set());
  return result;
}

export function sameSnapshot(a: Snapshot | undefined, b: Snapshot | undefined): boolean {
  if (!a || !b) return a === b;
  const keys = Object.keys(a);
  return keys.length === Object.keys(b).length && keys.every(key => a[key] === b[key]);
}

export function planSharedLink(destination: string, link: SharedLink): SharedChange | undefined {
  const target = path.join(destination, link.name);
  const stat = fs.lstatSync(target, { throwIfNoEntry: false });
  const marker = path.join(destination, copyMarker(link.name));
  const markerStat = fs.lstatSync(marker, { throwIfNoEntry: false });
  if (markerStat && (!markerStat.isFile() || markerStat.isSymbolicLink())) throw new Error(`Invalid copy marker: ${link.name}`);
  const markerBefore = markerStat ? fs.readFileSync(marker, "utf8") : undefined;
  if (!stat && !markerBefore) return { ...link };
  if (stat?.isSymbolicLink() && path.resolve(path.dirname(target), fs.readlinkSync(target)) === link.source) return undefined;
  if (stat?.isSymbolicLink() || !markerBefore) throw new Error(`Refusing to replace an existing entry: ${link.name}`);
  let saved: { version: number; source: string; files: Snapshot };
  try { saved = JSON.parse(markerBefore); } catch { throw new Error(`Invalid copy marker: ${link.name}`); }
  if (!saved || saved.version !== 1 || saved.source !== link.source || !saved.files || typeof saved.files !== "object" || Array.isArray(saved.files) ||
      !Object.hasOwn(saved.files, ".") || Object.values(saved.files).some(value => value !== "directory" && (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)))) {
    throw new Error(`Invalid copy marker: ${link.name}`);
  }
  if (!stat) return { ...link, markerBefore, copy: true };
  const before = snapshot(target)!;
  const desired = snapshot(link.source, true)!;
  // Local-only edits survive. A changed source may replace only an unchanged
  // managed copy (or a copy already identical to the new source).
  if (sameSnapshot(saved.files, desired)) return undefined;
  if (!sameSnapshot(before, saved.files) && !sameSnapshot(before, desired)) {
    throw new Error(`Conflicting local and dotfiles changes: ${link.name}`);
  }
  return { ...link, before, markerBefore, copy: true };
}

export function copyMetadata(source: string, files: Snapshot): string {
  return JSON.stringify({ version: 1, source, files }, null, 2) + "\n";
}

export type StagedLink = { source: string; target: string; directory?: boolean; copy?: boolean };

// All targets belong to caller-owned staging directories. A single Windows
// helper elevates only this link batch, never the Node runtime or its secrets.
export function stageSharedLinks(links: StagedLink[], copyWithoutElevation = false): void {
  const pending: StagedLink[] = [];
  for (const link of links) {
    fs.mkdirSync(path.dirname(link.target), { recursive: true });
    if (link.copy) {
      fs.cpSync(link.source, link.target, { recursive: true, dereference: true, errorOnExist: true, force: false });
      continue;
    }
    try { fs.symlinkSync(link.source, link.target, link.directory ? "dir" : "file"); } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "EPERM") throw error;
      if (process.platform === "win32") pending.push(link);
      else if (copyWithoutElevation) fs.cpSync(link.source, link.target, { recursive: true, dereference: true, errorOnExist: true, force: false });
      else throw error;
    }
  }
  if (!pending.length) return;
  const work = fs.mkdtempSync(path.join(os.tmpdir(), "dotfiles-links-"));
  try {
    const plan = path.join(work, "links.json");
    fs.writeFileSync(plan, JSON.stringify(pending.map(link => ({ Link: link.target, Target: link.source }))));
    const result = spawnSync(process.env.SETUP_POWERSHELL_PATH || "powershell.exe", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.resolve(__dirname, "../lib/windows-links.ps1"), "-PlanPath", plan,
    ], { encoding: "utf8", windowsHide: true });
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`Windows link setup failed: ${result.stderr || result.stdout}`);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}
