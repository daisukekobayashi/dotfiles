#!/usr/bin/env node
// Preview standalone Compose volume targets, or remove confirmed volumes after
// the stack stops. The provider manifest uses the same read-only planning rules.
import { spawnSync } from "node:child_process";
import { constants, closeSync, fstatSync, openSync, readFileSync, readSync, realpathSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import yaml from "../vendor/yaml/dist/index.js";

export const CLEANUP_MANIFEST_VERSION = 3;
const PROJECT = /^[a-z0-9][a-z0-9_-]*$/;
const VOLUME = /^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/;
const PROJECT_LABEL = "com.docker.compose.project";
const PROJECT_DIR_LABEL = PROJECT_LABEL + ".working_dir";
const PROJECT_FILES_LABEL = PROJECT_LABEL + ".config_files";
const NAME_FORMAT = "{{.Name}}";
const MAX_COMPOSE_BYTES = 256 * 1024;

const docker = (args, description) => {
  const result = spawnSync("docker", args, { encoding: "utf8", timeout: 15000 });
  // Docker diagnostics can include configuration values. Report the stage, not
  // the command's raw output, when the lookup or operation cannot be trusted.
  if (result.status !== 0 || result.error || result.stderr?.trim()) {
    throw new Error(description + " failed or could not be verified");
  }
  return result.stdout;
};

const lines = (value) => value.split("\n").filter(Boolean);
const json = (value, description) => {
  try {
    return JSON.parse(value);
  } catch {
    throw new Error(description + " returned malformed JSON");
  }
};
const projectArgs = (project) => ["--filter", "label=" + PROJECT_LABEL + "=" + project];
const projectContainers = (project, format) =>
  lines(docker(["ps", "-a", ...projectArgs(project), "--format", format], "Compose container lookup"));

export const inspectVolumeNames = (project) => {
  const filters = project ? projectArgs(project) : [];
  const names = lines(docker(["volume", "ls", ...filters, "--format", NAME_FORMAT], "Docker volume listing"));
  if (names.some((name) => !VOLUME.test(name)) || new Set(names).size !== names.length) {
    throw new Error("Docker volume listing returned invalid names");
  }
  return names.sort();
};

const daemonId = () => {
  const id = docker(["info", "--format", "{{.ID}}"], "Docker daemon lookup").trim();
  if (!/^[a-zA-Z0-9:_-]+$/.test(id)) throw new Error("Docker daemon identity cannot be verified");
  return id;
};

const volumeIdentity = (project, name) => {
  const result = json(docker(["volume", "inspect", "--", name], "Docker volume inspection"), "Docker volume inspection");
  const volume = Array.isArray(result) && result.length === 1 ? result[0] : null;
  const { Name, Driver, CreatedAt, Labels } = volume ?? {};
  if (Name !== name || Labels?.[PROJECT_LABEL] !== project || !VOLUME.test(Driver ?? "") ||
      typeof CreatedAt !== "string" || !Number.isFinite(Date.parse(CreatedAt))) {
    throw new Error("Docker volume " + name + " ownership or identity cannot be verified");
  }
  return { name, driver: Driver, createdAt: CreatedAt };
};

const within = (dir, file) => file === dir || file.startsWith(dir + path.sep);

const configFiles = (project, dir) => {
  const format = "{{json (.Label \"" + PROJECT_DIR_LABEL + "\")}}\t{{json (.Label \"" + PROJECT_FILES_LABEL + "\")}}";
  const rows = projectContainers(project, format);
  if (rows.length === 0 || new Set(rows).size !== 1) throw new Error("Compose configuration is ambiguous");
  const [directory, files] = rows[0].split("\t").map((field) => json(field, "Compose configuration labels"));
  if (directory !== dir || typeof files !== "string" || !files) throw new Error("Compose configuration is unknown");
  return files.split(",");
};

const configText = (dir, files) => {
  // Resolve only the one Compose file named by the containers. A local YAML
  // read cannot traverse Compose references or start a Compose resource loader.
  const [file] = files;
  if (files.length !== 1 || !path.isAbsolute(file) || !within(dir, file) ||
      realpathSync(dir) !== dir || realpathSync(file) !== file) {
    throw new Error("Compose configuration is not one verified local file");
  }
  const fd = openSync(file, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0) | (constants.O_NONBLOCK ?? 0));
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.size > MAX_COMPOSE_BYTES) throw new Error("Compose configuration size or type is unsupported");
    const buffer = Buffer.alloc(MAX_COMPOSE_BYTES + 1);
    let length = 0;
    while (length < buffer.length) {
      const bytes = readSync(fd, buffer, length, buffer.length - length, null);
      if (bytes === 0) break;
      length += bytes;
    }
    if (length > MAX_COMPOSE_BYTES) throw new Error("Compose configuration exceeds the size limit");
    return new TextDecoder("utf-8", { fatal: true }).decode(buffer.subarray(0, length));
  } finally {
    closeSync(fd);
  }
};

const managedNames = (project, dir, files) => {
  const document = yaml.parseDocument(configText(dir, files), { strict: true, uniqueKeys: true, stringKeys: true, prettyErrors: false });
  if (document.errors.length || document.warnings.length || document.directives?.yaml.explicit) {
    throw new Error("Compose YAML could not be verified");
  }
  yaml.visit(document, (_key, node) => {
    if (yaml.isAlias(node) || node.tag || node.anchor || (yaml.isPair(node) && node.key?.value === "<<")) {
      throw new Error("Compose configuration uses unsupported YAML indirection");
    }
  });
  const model = document.toJS({ mapAsMap: true, maxAliasCount: 0 });
  if (!(model instanceof Map) || model.has("include")) throw new Error("Compose configuration is not a direct local model");
  const services = model.get("services") ?? new Map();
  if (!(services instanceof Map) || [...services.values()].some((service) => !(service instanceof Map) || service.has("extends"))) {
    throw new Error("Compose services are not directly declared");
  }
  const volumes = model.get("volumes") ?? new Map();
  if (!(volumes instanceof Map)) throw new Error("Compose volume declarations could not be verified");

  const names = new Map();
  for (const [key, volume] of volumes) {
    if (!VOLUME.test(key) || (volume !== null && !(volume instanceof Map))) {
      throw new Error("Compose volume declaration is unsupported");
    }
    const name = volume?.has("name") ? volume.get("name") : project + "_" + key;
    if (typeof name !== "string" || !VOLUME.test(name)) throw new Error("Compose volume name is not static");
    // Multiple declarations can refer to one name; none of them grant
    // removal in that case. An unspecified external flag means managed.
    names.set(name, !names.has(name) && (!volume?.has("external") || volume.get("external") === false));
  }
  return new Set([...names].filter(([, managed]) => managed).map(([name]) => name));
};

// An unavailable model or identity keeps the affected volumes. Names observed
// through the project label remain visible but do not imply deletion consent.
export const planVolumeRemoval = (project, dir, volumes) => {
  const keep = { daemon: null, configFiles: [], deleteVolumes: [] };
  if (volumes.length === 0 || !PROJECT.test(project)) return keep;

  let files, managed, daemon;
  try {
    daemon = daemonId();
    if (dir === "-") {
      if (projectContainers(project, "{{.ID}}").length > 0) return keep;
      files = [];
      managed = new Set(volumes);
    } else {
      files = configFiles(project, dir);
      managed = managedNames(project, dir, files);
    }
  } catch {
    return keep;
  }

  const deleteVolumes = [];
  for (const name of volumes) {
    if (!VOLUME.test(name) || !managed.has(name)) continue;
    try {
      deleteVolumes.push(volumeIdentity(project, name));
    } catch {
      // Without stable identity, this individual volume stays.
    }
  }
  return deleteVolumes.length > 0 ? { daemon, configFiles: files, deleteVolumes } : keep;
};

const checkedItem = (item) => {
  const { project, working_dir: dir, volumes, deleteVolumes, daemon, configFiles: files } = item ?? {};
  if (!PROJECT.test(project ?? "") || typeof dir !== "string" || (dir !== "-" && !path.isAbsolute(dir)) ||
      !Array.isArray(volumes) || volumes.some((name) => typeof name !== "string" || !VOLUME.test(name)) ||
      !Array.isArray(deleteVolumes) || !Array.isArray(files) ||
      (deleteVolumes.length > 0 && (typeof daemon !== "string" || files.length !== (dir === "-" ? 0 : 1))) ||
      files.some((file) => typeof file !== "string" || !path.isAbsolute(file)) ||
      deleteVolumes.some((volume) => !volume || !volumes.includes(volume.name) ||
        typeof volume.createdAt !== "string" || !VOLUME.test(volume.driver ?? "")) ||
      new Set(deleteVolumes.map(({ name }) => name)).size !== deleteVolumes.length) {
    throw new Error("invalid Compose volume confirmation; preview and confirm again");
  }
  return item;
};

const checkDaemon = (item) => {
  if (daemonId() !== item.daemon) throw new Error("Docker daemon changed since confirmation");
};

const checkIdentity = (item, volume) => {
  const live = volumeIdentity(item.project, volume.name);
  if (live.driver !== volume.driver || live.createdAt !== volume.createdAt) {
    throw new Error("Docker volume " + volume.name + " changed since confirmation");
  }
};

const checkEligibility = (item, volumes) => {
  if (item.working_dir === "-" || volumes.length === 0) return;
  const managed = managedNames(item.project, item.working_dir, item.configFiles);
  if (volumes.some(({ name }) => !managed.has(name))) {
    throw new Error("Compose volume eligibility changed; preview and confirm again");
  }
};

// Inspect globally so a present name whose project label changed cannot be
// mistaken for a removed volume. Return confirmed present names in order.
export const remainingVolumeRemovals = (item, { verifyEligibility = false } = {}) => {
  checkedItem(item);
  if (item.deleteVolumes.length === 0) return [];
  checkDaemon(item);
  const all = new Set(inspectVolumeNames());
  const remaining = item.deleteVolumes.filter((volume) => {
    if (!all.has(volume.name)) return false;
    checkIdentity(item, volume);
    return true;
  });
  if (verifyEligibility) checkEligibility(item, remaining);
  return remaining;
};

const removeVolumes = (item) => {
  checkedItem(item);
  if (item.deleteVolumes.length === 0) return;
  const added = inspectVolumeNames(item.project).filter((name) => !item.volumes.includes(name));
  if (added.length > 0) throw new Error("new Compose volumes require a new preview and confirmation");
  const remaining = remainingVolumeRemovals(item, { verifyEligibility: true });
  for (const volume of remaining) {
    checkDaemon(item);
    if (projectContainers(item.project, "{{.ID}}").length > 0) {
      throw new Error("Compose project " + item.project + " still has containers; its volumes were kept");
    }
    checkEligibility(item, [volume]);
    checkIdentity(item, volume);
    docker(["volume", "rm", "--", volume.name], "removing Docker volume " + volume.name);
    process.stdout.write("removed " + volume.name + "\n");
  }
  if (remainingVolumeRemovals(item).length > 0) {
    throw new Error("confirmed Docker volumes remain after removal");
  }
};

const readConfirmation = (file) => {
  if (!path.isAbsolute(file)) throw new Error("confirmation path must be absolute");
  const fd = openSync(file, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0) | (constants.O_NONBLOCK ?? 0));
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || (stat.mode & 0o077) !== 0 || (process.getuid && stat.uid !== process.getuid())) {
      throw new Error("confirmation must be a private regular file");
    }
    const manifest = JSON.parse(readFileSync(fd, "utf8"));
    if (manifest?.version !== CLEANUP_MANIFEST_VERSION) throw new Error("preview and confirm volumes again with the current format");
    return manifest;
  } finally {
    closeSync(fd);
  }
};

const preview = (project, dir, file, ...selected) => {
  if (!PROJECT.test(project) || (dir !== "-" && !path.isAbsolute(dir)) || !path.isAbsolute(file)) {
    throw new Error("use a Compose project name and absolute paths");
  }
  const volumes = inspectVolumeNames(project);
  if (selected.some((name) => !volumes.includes(name))) throw new Error("selected names do not belong to the Compose project");
  const plan = planVolumeRemoval(project, dir, selected.length === 0 ? volumes : [...new Set(selected)].sort());
  const item = { project, working_dir: dir, volumes, ...plan };
  const deletion = new Set(item.deleteVolumes.map(({ name }) => name));
  writeFileSync(file, JSON.stringify({ version: CLEANUP_MANIFEST_VERSION, standalone: item }), { flag: "wx", mode: 0o600 });
  process.stdout.write("Delete: " + (Array.from(deletion).join(", ") || "none") +
    "\nRetain: " + (volumes.filter((name) => !deletion.has(name)).join(", ") || "none") + "\n");
};

const apply = (file, scope) => {
  if (process.platform === "win32") {
    throw new Error("Docker volume deletion requires POSIX confirmation checks; run cleanup through WSL");
  }
  const confirmation = readConfirmation(file);
  if (confirmation.standalone) {
    if (confirmation.standalone.project !== scope) throw new Error("standalone confirmation names a different project");
    removeVolumes(confirmation.standalone);
    return;
  }

  if (!path.isAbsolute(scope) || confirmation.worktree !== realpathSync(scope)) {
    throw new Error("confirmation names a different worktree");
  }
  if (confirmation.compose?.status === "unavailable") return;
  if (confirmation.compose?.status !== "ok" || !Array.isArray(confirmation.compose.items)) {
    throw new Error("invalid Compose confirmation");
  }
  const items = confirmation.compose.items.map(checkedItem);
  for (const item of items) {
    if (item.deleteVolumes.length > 0 && (item.reason !== "under target" || !within(confirmation.worktree, item.working_dir))) {
      throw new Error("confirmation includes volumes outside its worktree project");
    }
  }
  for (const item of items) removeVolumes(item);
};

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [command, ...args] = process.argv.slice(2);
    if (command === "preview" && args.length >= 3) preview(...args);
    else if (command === "apply" && args.length === 2) apply(...args);
    else throw new Error("usage: remove-compose-volumes.mjs preview <project> <working-dir|-> <out> [<volume> ...] or apply <confirmed-file> <worktree|project>");
  } catch (error) {
    // Keep unexpected parsing or file errors from emitting config/JSON values.
    const code = error.code;
    const message = error instanceof SyntaxError ? "could not parse Compose output or confirmation" :
      code ? "could not read or write confirmation (" + code + ")" : error.message;
    process.stderr.write("Compose volume cleanup: " + message + "\n");
    process.exitCode = 1;
  }
}
