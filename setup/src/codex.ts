import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { isDeepStrictEqual } from "node:util";
import { parse, stringify } from "smol-toml";

type Table = Record<string, unknown>;
type Baseline = { version: 1 | 2; defaultProfile: string; azureProvider?: Table; files: Record<string, string> };
type Change = { name: string; before: string | undefined; after: string };

const markerName = ".dotfiles-azure.json";
const defaultProfile = "azure_gpt-6_1-sol_max";

function table(value: unknown): value is Table {
  return value !== null && typeof value === "object" &&
    (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
}

function readToml(text: string, name: string): Table {
  try {
    return parse(text) as Table;
  } catch {
    // Parser excerpts can contain local configuration values.
    throw new Error(`Invalid TOML: ${name}`);
  }
}

function sharedConfig(config: Table): Table {
  delete config.projects;
  delete config.forced_login_method;
  delete config.forced_chatgpt_workspace_id;
  delete config.log_dir;
  delete config.sqlite_home;
  if (table(config.hooks)) {
    delete config.hooks.state;
    if (Object.keys(config.hooks).length === 0) delete config.hooks;
  }
  if (table(config.tui)) {
    delete config.tui.model_availability_nux;
    delete config.tui.screen_reader_detection_done;
    if (Object.keys(config.tui).length === 0) delete config.tui;
  }
  if (table(config.notice)) {
    delete config.notice.model_migrations;
    if (Object.keys(config.notice).length === 0) delete config.notice;
  }
  return config;
}

function overlay(base: Table, overrides: Table): Table {
  const result: Table = Object.assign(Object.create(null), base);
  for (const [key, value] of Object.entries(overrides)) {
    result[key] = table(value) && table(result[key]) ? overlay(result[key], value) : value;
  }
  return result;
}

function validateBaseUrl(value: unknown): void {
  const message = "Azure base URL must be an http(s) base_url without credentials, query parameters or fragment";
  if (typeof value !== "string" || value.trim() !== value || /\s/.test(value)) throw new Error(message);
  try {
    const url = new URL(value);
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) {
      throw new Error();
    }
  } catch {
    throw new Error(message);
  }
}

function resolveAzureProvider(baseline: Baseline | undefined, baseUrl: string | undefined, apiVersion: string | undefined): Table {
  let saved = baseline?.azureProvider;
  if (baseline?.version === 1) {
    const previous = readToml(baseline.files["config.toml"] ?? "", "previous config.toml");
    if (table(previous.model_providers) && table(previous.model_providers.azure)) saved = previous.model_providers.azure;
  }
  if (!saved && baseUrl === undefined) throw new Error("First generation requires --azure-base-url BASE_URL");
  const provider = overlay({ name: "Azure", env_key: "AZURE_OPENAI_API_KEY", wire_api: "responses", requires_openai_auth: false }, saved ?? {});
  if (baseUrl !== undefined) provider.base_url = baseUrl;
  validateBaseUrl(provider.base_url);
  if (provider.env_key !== "AZURE_OPENAI_API_KEY" || provider.wire_api !== "responses" || provider.requires_openai_auth !== false) {
    throw new Error("The saved Azure provider must use AZURE_OPENAI_API_KEY and Responses without OpenAI login");
  }
  if (provider.query_params !== undefined && !table(provider.query_params)) throw new Error("Invalid saved Azure query parameters");
  if (apiVersion !== undefined) {
    const params = overlay({}, table(provider.query_params) ? provider.query_params : {});
    if (apiVersion === "none") delete params["api-version"];
    else {
      if (!apiVersion || /\s/.test(apiVersion)) throw new Error("Azure API version must be a non-empty value or 'none'");
      params["api-version"] = apiVersion;
    }
    if (Object.keys(params).length > 0) provider.query_params = params;
    else delete provider.query_params;
  }
  return provider;
}

function azureConfig(config: Table, provider: Table): Table {
  return {
    ...config,
    model_provider: "azure",
    cli_auth_credentials_store: "file",
    model_providers: { azure: provider },
  };
}

function mergeLocal(previous: unknown, current: unknown, desired: unknown, key: string): unknown {
  if (isDeepStrictEqual(current, previous)) return desired;
  if (isDeepStrictEqual(previous, desired) || isDeepStrictEqual(current, desired)) return current;
  if (table(current) && table(desired) && (previous === undefined || table(previous))) {
    const old = previous ?? {};
    const merged: Table = Object.create(Object.getPrototypeOf(current));
    for (const name of new Set([...Object.keys(old), ...Object.keys(current), ...Object.keys(desired)])) {
      const value = mergeLocal(old[name], current[name], desired[name], `${key}.${name}`);
      if (value !== undefined) merged[name] = value;
    }
    return merged;
  }
  throw new Error(`Conflicting local and dotfiles changes: ${key}`);
}

function assertAzure(config: Table, name: string): void {
  const providers = config.model_providers;
  if (config.model_provider !== "azure" || config.cli_auth_credentials_store !== "file" ||
      !table(providers) || !table(providers.azure) || providers.azure.requires_openai_auth !== false ||
      providers.azure.env_key !== "AZURE_OPENAI_API_KEY") {
    throw new Error(`Azure provider or credential isolation was changed locally: ${name}`);
  }
}

function readOptional(file: string): string | undefined {
  try {
    return fs.readFileSync(file, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
    throw new Error(`Cannot read file: ${file}`);
  }
}

function checkTarget(home: string, name: string): void {
  // In particular, never follow a config link back into the main Codex home.
  const paths = [home];
  let current = home;
  for (const segment of name.split("/")) {
    current = path.join(current, segment);
    paths.push(current);
  }
  for (let index = 0; index < paths.length; index++) {
    let stat: fs.Stats;
    try {
      stat = fs.lstatSync(paths[index]);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") continue;
      throw new Error(`Cannot inspect target: ${paths[index]}`);
    }
    if (stat.isSymbolicLink() || (index < paths.length - 1 ? !stat.isDirectory() : !stat.isFile())) {
      throw new Error(`Refusing a symlink or unexpected target type: ${paths[index]}`);
    }
  }
}

function readBaseline(home: string): { text: string | undefined; baseline: Baseline | undefined } {
  checkTarget(home, markerName);
  const text = readOptional(path.join(home, markerName));
  if (text === undefined) return { text, baseline: undefined };
  try {
    const value = JSON.parse(text);
    if (![1, 2].includes(value.version) || (value.version === 2 && !table(value.azureProvider)) ||
        typeof value.defaultProfile !== "string" || !table(value.files) ||
        !Object.values(value.files).every(item => typeof item === "string")) throw new Error();
    return { text, baseline: value };
  } catch {
    throw new Error(`Invalid Azure generation metadata: ${path.join(home, markerName)}`);
  }
}

function desiredFiles(root: string, profile: string, provider: Table): Record<string, string> {
  const codexDir = path.join(root, "codex");
  const base = sharedConfig(readToml(fs.readFileSync(path.join(codexDir, "config.toml"), "utf8"), "codex/config.toml"));
  const profiles: Record<string, Table> = {};
  for (const name of fs.readdirSync(codexDir).sort()) {
    if (!/^azure_[A-Za-z0-9_-]+\.config\.toml$/.test(name)) continue;
    const config = sharedConfig(readToml(fs.readFileSync(path.join(codexDir, name), "utf8"), `codex/${name}`));
    if (config.model_provider !== "azure" || typeof config.model !== "string") {
      throw new Error(`Expected an Azure model profile: codex/${name}`);
    }
    profiles[name] = azureConfig(overlay(base, config), provider);
  }
  const selected = profiles[`${profile}.config.toml`];
  if (!selected) throw new Error(`Azure profile not found in dotfiles: ${profile}`);
  const files: Record<string, string> = { "config.toml": stringify(selected) };
  for (const [name, config] of Object.entries(profiles)) files[name] = stringify(config);
  files["hooks.json"] = fs.readFileSync(path.join(codexDir, "hooks.json"), "utf8");
  try {
    JSON.parse(files["hooks.json"]);
  } catch {
    throw new Error("Invalid JSON: codex/hooks.json");
  }
  files["rules/user.rules"] = fs.readFileSync(path.join(codexDir, "rules/user.rules"), "utf8");
  const baseRules = fs.readFileSync(path.join(root, "ai-rules/base/global.md"), "utf8");
  const agentRules = fs.readFileSync(path.join(root, "ai-rules/agents/codex.md"), "utf8");
  files["AGENTS.md"] = baseRules + (agentRules.trim() ? `\n---\n\n${agentRules}` : "") + "\n";
  return files;
}

function planChanges(home: string, desired: Record<string, string>, previous: Baseline | undefined): Change[] {
  const changes: Change[] = [];
  for (const [name, source] of Object.entries(desired)) {
    checkTarget(home, name);
    const before = readOptional(path.join(home, name));
    const old = previous?.files[name];
    if (before !== undefined && old === undefined) {
      throw new Error(`Refusing to overwrite an unmanaged file: ${path.join(home, name)}`);
    }
    let after = source;
    if (name.endsWith(".toml") && before !== undefined) {
      const current = readToml(before, path.join(home, name));
      const merged = mergeLocal(readToml(old!, `previous ${name}`), current, readToml(source, name), name) as Table;
      assertAzure(merged, name);
      after = isDeepStrictEqual(current, merged) ? before : stringify(merged);
    } else if (before !== undefined) {
      after = mergeLocal(old, before, source, name) as string;
    }
    if (after !== before) changes.push({ name, before, after });
  }
  return changes;
}

function applyChanges(home: string, changes: Change[]): void {
  if (changes.length === 0) return;
  fs.mkdirSync(home, { recursive: true, mode: 0o700 });
  const stage = fs.mkdtempSync(path.join(home, ".dotfiles-azure-stage-"));
  const applied: Change[] = [];
  let backup: string | undefined;
  try {
    for (let index = 0; index < changes.length; index++) {
      fs.writeFileSync(path.join(stage, `${index}.new`), changes[index].after, { mode: 0o600 });
    }
    // Recheck all files before replacing any of them.
    for (const change of changes) {
      checkTarget(home, change.name);
      if (readOptional(path.join(home, change.name)) !== change.before) {
        throw new Error(`Target changed during generation: ${path.join(home, change.name)}`);
      }
    }
    if (changes.some(change => change.before !== undefined)) {
      checkTarget(home, ".dotfiles-azure-backups/placeholder");
      fs.mkdirSync(path.join(home, ".dotfiles-azure-backups"), { recursive: true, mode: 0o700 });
      backup = fs.mkdtempSync(path.join(home, ".dotfiles-azure-backups/update-"));
      for (const change of changes) {
        if (change.before === undefined) continue;
        const file = path.join(backup, change.name);
        fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
        fs.writeFileSync(file, change.before, { mode: 0o600 });
      }
    }
    for (let index = 0; index < changes.length; index++) {
      const change = changes[index];
      const file = path.join(home, change.name);
      fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
      checkTarget(home, change.name);
      if (readOptional(file) !== change.before) throw new Error(`Target changed during generation: ${file}`);
      fs.renameSync(path.join(stage, `${index}.new`), file);
      applied.push(change);
    }
  } catch (error) {
    for (const change of applied.reverse()) {
      const file = path.join(home, change.name);
      checkTarget(home, change.name);
      if (readOptional(file) !== change.after) {
        throw new Error(`Rollback stopped because a target changed: ${file}. Backup: ${backup ?? stage}`);
      }
      if (change.before === undefined) fs.unlinkSync(file);
      else {
        const restore = path.join(stage, "restore");
        fs.writeFileSync(restore, change.before, { mode: 0o600 });
        fs.renameSync(restore, file);
      }
    }
    throw error;
  } finally {
    // Only remove temporary files created by this invocation.
    for (const name of fs.readdirSync(stage)) fs.unlinkSync(path.join(stage, name));
    fs.rmdirSync(stage);
  }
  if (backup) console.log(`Previous managed files backed up in ${backup}`);
}

export function main(args = process.argv.slice(2)): void {
  let profile: string | undefined;
  let baseUrl: string | undefined;
  let apiVersion: string | undefined;
  let dryRun = process.env.SETUP_DRY_RUN === "1";
  for (let index = 0; index < args.length; index++) {
    if (args[index] === "--help" || args[index] === "-h") {
      console.log("Usage: ./setup.sh codex [--azure-base-url BASE_URL] [--azure-api-version VERSION|none] [--profile AZURE_PROFILE] [--dry-run]\n" +
        "Generate ~/.codex-azure from shared dotfiles settings.\n" +
        "First generation requires --azure-base-url. Later runs reuse the saved Azure provider.\n" +
        "Omit --azure-api-version on first generation to leave api-version unset; 'none' removes a saved value.");
      return;
    }
    if (args[index] === "--dry-run") dryRun = true;
    else if (["--profile", "--azure-base-url", "--azure-api-version"].includes(args[index])) {
      const option = args[index];
      const value = args[++index];
      if (!value || value.startsWith("--")) throw new Error(`${option} requires a value`);
      if (option === "--profile") profile = value;
      else if (option === "--azure-base-url") baseUrl = value;
      else apiVersion = value;
    } else throw new Error("Unknown codex setup argument; see --help");
  }
  const root = path.resolve(process.env.SETUP_DOTFILES_ROOT || path.join(__dirname, ".."));
  const home = path.resolve(process.env.SETUP_HOME || os.homedir(), ".codex-azure");
  const { text, baseline } = readBaseline(home);
  profile ??= baseline?.defaultProfile ?? defaultProfile;
  if (!/^azure_[A-Za-z0-9_-]+$/.test(profile)) throw new Error("Expected an Azure profile name (without .config.toml)");
  const provider = resolveAzureProvider(baseline, baseUrl, apiVersion);
  const desired = desiredFiles(root, profile, provider);
  const changes = planChanges(home, desired, baseline);
  const metadata: Baseline = { version: 2, defaultProfile: profile, azureProvider: provider, files: desired };
  const after = JSON.stringify(metadata, null, 2) + "\n";
  if (after !== text) changes.push({ name: markerName, before: text, after });
  for (const change of changes) console.log(`${dryRun ? "Would write" : "Updating"} ${path.join(home, change.name)}`);
  if (dryRun) return;
  applyChanges(home, changes);
  console.log(`Azure home ${changes.length ? "generated" : "already up to date"}: ${home} (${profile})`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    // Avoid printing parser output or config values from nested errors.
    console.error(`codex setup: ${error instanceof Error ? error.message : "Generation failed"}`);
    process.exitCode = 1;
  }
}
