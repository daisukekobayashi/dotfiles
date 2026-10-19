"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.main = main;
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const node_util_1 = require("node:util");
const smol_toml_1 = require("smol-toml");
const providerNames = { azure: "Azure", openai: "OpenAI", chatgpt: "ChatGPT" };
function markerName() {
    return ".dotfiles-env.json";
}
function validEnv(name) {
    return /^[a-z][a-z0-9_-]{0,63}$/.test(name) && !/^(con|prn|aux|nul|com[0-9]|lpt[0-9])$/.test(name);
}
function envHome(home, env) {
    if (env === "default")
        return path.join(home, ".codex");
    if (env === "azure" || env === "openai")
        return path.join(home, `.codex-${env}`);
    const root = path.join(home, ".codex-envs");
    if (fs.existsSync(root) && (fs.lstatSync(root).isSymbolicLink() || !fs.lstatSync(root).isDirectory())) {
        throw new Error("Refusing a symlink or unexpected Codex environment directory");
    }
    return path.join(root, env);
}
function table(value) {
    return value !== null && typeof value === "object" &&
        (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
}
function readToml(text, name) {
    try {
        return (0, smol_toml_1.parse)(text);
    }
    catch {
        // Parser excerpts can contain local configuration values.
        throw new Error(`Invalid TOML: ${name}`);
    }
}
function sharedConfig(config) {
    delete config.projects;
    delete config.forced_login_method;
    delete config.forced_chatgpt_workspace_id;
    delete config.log_dir;
    delete config.sqlite_home;
    if (table(config.hooks)) {
        delete config.hooks.state;
        if (Object.keys(config.hooks).length === 0)
            delete config.hooks;
    }
    if (table(config.tui)) {
        delete config.tui.model_availability_nux;
        delete config.tui.screen_reader_detection_done;
        if (Object.keys(config.tui).length === 0)
            delete config.tui;
    }
    if (table(config.notice)) {
        delete config.notice.model_migrations;
        if (Object.keys(config.notice).length === 0)
            delete config.notice;
    }
    return config;
}
function overlay(base, overrides) {
    const result = Object.assign(Object.create(null), base);
    for (const [key, value] of Object.entries(overrides)) {
        result[key] = table(value) && table(result[key]) ? overlay(result[key], value) : value;
    }
    return result;
}
function validateBaseUrl(value, label = "Azure") {
    const message = `${label} base URL must be an http(s) base_url without credentials, query parameters or fragment`;
    if (typeof value !== "string" || value.trim() !== value || /\s/.test(value))
        throw new Error(message);
    try {
        const url = new URL(value);
        if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) {
            throw new Error();
        }
    }
    catch {
        throw new Error(message);
    }
}
function resolveAzureProvider(baseline, baseUrl, apiVersion, apiKeyEnv) {
    let saved = baseline?.azureProvider;
    if (baseline?.version === 1) {
        const previous = readToml(baseline.files["config.toml"] ?? "", "previous config.toml");
        if (table(previous.model_providers) && table(previous.model_providers.azure))
            saved = previous.model_providers.azure;
    }
    if (!saved && baseUrl === undefined)
        throw new Error("First generation requires --azure-base-url BASE_URL (or --base-url BASE_URL)");
    const provider = overlay({ name: "Azure", env_key: "AZURE_OPENAI_API_KEY", wire_api: "responses", requires_openai_auth: false }, saved ?? {});
    if (baseUrl !== undefined)
        provider.base_url = baseUrl;
    if (apiKeyEnv !== undefined)
        provider.env_key = apiKeyEnv;
    validateBaseUrl(provider.base_url);
    if (typeof provider.env_key !== "string" || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(provider.env_key) || provider.wire_api !== "responses" || provider.requires_openai_auth !== false) {
        throw new Error("The saved Azure provider must use a credential environment variable and Responses without OpenAI login");
    }
    if (provider.query_params !== undefined && !table(provider.query_params))
        throw new Error("Invalid saved Azure query parameters");
    if (apiVersion !== undefined) {
        const params = overlay({}, table(provider.query_params) ? provider.query_params : {});
        if (apiVersion === "none")
            delete params["api-version"];
        else {
            if (!apiVersion || /\s/.test(apiVersion))
                throw new Error("Azure API version must be a non-empty value or 'none'");
            params["api-version"] = apiVersion;
        }
        if (Object.keys(params).length > 0)
            provider.query_params = params;
        else
            delete provider.query_params;
    }
    return provider;
}
function resolveOpenAIProvider(baseline, baseUrl) {
    const provider = { base_url: baseUrl ?? baseline?.openaiProvider?.base_url ?? "https://api.openai.com/v1" };
    validateBaseUrl(provider.base_url, "OpenAI");
    return provider;
}
function apiConfig(config, kind, provider) {
    if (kind === "chatgpt") {
        const result = { ...config, model_provider: "openai", forced_login_method: "chatgpt", cli_auth_credentials_store: "file" };
        delete result.model_providers;
        delete result.openai_base_url;
        return result;
    }
    if (kind === "openai") {
        const result = {
            ...config,
            model_provider: "openai",
            forced_login_method: "api",
            cli_auth_credentials_store: "file",
            openai_base_url: provider.base_url,
        };
        delete result.model_providers;
        return result;
    }
    return {
        ...config,
        model_provider: "azure",
        cli_auth_credentials_store: "file",
        model_providers: { azure: provider },
    };
}
function mergeLocal(previous, current, desired, key, pruneInheritedTables = false) {
    if ((0, node_util_1.isDeepStrictEqual)(current, previous))
        return desired;
    if ((0, node_util_1.isDeepStrictEqual)(previous, desired) || (0, node_util_1.isDeepStrictEqual)(current, desired))
        return current;
    // A legacy full profile can contain local runtime entries alongside inherited
    // preferences. Remove the unchanged preferences while retaining those entries.
    if (pruneInheritedTables && table(previous) && table(current) && desired === undefined)
        desired = {};
    if (table(current) && table(desired) && (previous === undefined || table(previous))) {
        const old = previous ?? {};
        const merged = Object.create(Object.getPrototypeOf(current));
        for (const name of new Set([...Object.keys(old), ...Object.keys(current), ...Object.keys(desired)])) {
            const value = mergeLocal(old[name], current[name], desired[name], `${key}.${name}`, pruneInheritedTables);
            if (value !== undefined)
                merged[name] = value;
        }
        return merged;
    }
    throw new Error(`Conflicting local and dotfiles changes: ${key}`);
}
function assertProvider(config, name, kind, envKey = "AZURE_OPENAI_API_KEY") {
    if (kind === "chatgpt") {
        if (config.model_provider !== "openai" || config.cli_auth_credentials_store !== "file" || config.forced_login_method !== "chatgpt") {
            throw new Error(`ChatGPT provider or credential isolation was changed locally: ${name}`);
        }
        return;
    }
    if (kind === "openai") {
        if (config.model_provider !== "openai" || config.cli_auth_credentials_store !== "file" ||
            config.forced_login_method !== "api" || (table(config.model_providers) && config.model_providers.openai !== undefined)) {
            throw new Error(`OpenAI provider or credential isolation was changed locally: ${name}`);
        }
        validateBaseUrl(config.openai_base_url, "OpenAI");
        return;
    }
    const providers = config.model_providers;
    if (config.model_provider !== "azure" || config.cli_auth_credentials_store !== "file" ||
        !table(providers) || !table(providers.azure) || providers.azure.requires_openai_auth !== false ||
        providers.azure.env_key !== envKey) {
        throw new Error(`Azure provider or credential isolation was changed locally: ${name}`);
    }
}
function readOptional(file) {
    try {
        return fs.readFileSync(file, "utf8");
    }
    catch (error) {
        if (error.code === "ENOENT")
            return undefined;
        throw new Error(`Cannot read file: ${file}`);
    }
}
function checkTarget(home, name) {
    // In particular, never follow a config link back into the main Codex home.
    const paths = [home];
    let current = home;
    for (const segment of name.split("/")) {
        current = path.join(current, segment);
        paths.push(current);
    }
    for (let index = 0; index < paths.length; index++) {
        let stat;
        try {
            stat = fs.lstatSync(paths[index]);
        }
        catch (error) {
            if (error.code === "ENOENT")
                continue;
            throw new Error(`Cannot inspect target: ${paths[index]}`);
        }
        if (stat.isSymbolicLink() || (index < paths.length - 1 ? !stat.isDirectory() : !stat.isFile())) {
            throw new Error(`Refusing a symlink or unexpected target type: ${paths[index]}`);
        }
    }
}
function readBaseline(home, env) {
    let selected = { text: undefined, baseline: undefined };
    for (const marker of [markerName(), ".dotfiles-azure.json", ".dotfiles-openai.json"]) {
        checkTarget(home, marker);
        const text = readOptional(path.join(home, marker));
        if (text === undefined)
            continue;
        try {
            const value = JSON.parse(text);
            const kind = marker === markerName() ? value.provider : marker === ".dotfiles-azure.json" ? "azure" : "openai";
            if (!Object.hasOwn(providerNames, kind) || ![1, 2, 3].includes(value.version) ||
                (marker === markerName() ? value.version !== 3 || value.env !== env : value.version === 3 || (kind === "openai" && value.version !== 2)) ||
                (value.version >= 2 && kind !== "chatgpt" && !table(value[kind === "azure" ? "azureProvider" : "openaiProvider"])) ||
                typeof value.defaultProfile !== "string" || !table(value.files) ||
                !Object.values(value.files).every(item => typeof item === "string"))
                throw new Error();
            if (selected.kind && selected.kind !== kind)
                throw new Error();
            if (!selected.baseline)
                selected = { text: marker === markerName() ? text : undefined, baseline: value, kind };
        }
        catch {
            throw new Error(`Invalid or conflicting Codex environment metadata: ${path.join(home, marker)}`);
        }
    }
    return selected;
}
function profileCatalog(root, kind) {
    let catalog;
    try {
        catalog = JSON.parse(fs.readFileSync(path.join(root, "codex/env-profiles.json"), "utf8"));
    }
    catch {
        throw new Error("Invalid Codex env-profiles.json");
    }
    const entry = table(catalog) && table(catalog[kind]) ? catalog[kind] : undefined;
    if (!entry || typeof entry.defaultProfile !== "string" || !Array.isArray(entry.profiles) ||
        !entry.profiles.includes(entry.defaultProfile) ||
        !entry.profiles.every(name => typeof name === "string" && /^[A-Za-z0-9_-]+$/.test(name))) {
        throw new Error(`Invalid ${providerNames[kind]} profile catalog`);
    }
    return { defaultProfile: entry.defaultProfile, profiles: entry.profiles };
}
function desiredFiles(root, profile, kind, provider) {
    const codexDir = path.join(root, "codex");
    const base = sharedConfig(readToml(fs.readFileSync(path.join(codexDir, "config.toml"), "utf8"), "codex/config.toml"));
    const catalog = profileCatalog(root, kind);
    const profiles = {};
    for (const slug of catalog.profiles) {
        const name = `${slug}.config.toml`;
        const config = readToml(fs.readFileSync(path.join(codexDir, "profiles", name), "utf8"), `codex/profiles/${name}`);
        if (typeof config.model !== "string" || typeof config.model_reasoning_effort !== "string" ||
            Object.keys(config).some(key => !["model", "model_reasoning_effort"].includes(key))) {
            throw new Error(`Expected only model and effort in codex/profiles/${name}`);
        }
        profiles[name] = config;
    }
    const selected = profiles[`${profile}.config.toml`];
    if (!selected)
        throw new Error(`${providerNames[kind]} profile not found in dotfiles: ${profile}`);
    const files = { "config.toml": (0, smol_toml_1.stringify)(apiConfig(overlay(base, selected), kind, provider)) };
    for (const [name, config] of Object.entries(profiles))
        files[name] = (0, smol_toml_1.stringify)(config);
    files["hooks.json"] = fs.readFileSync(path.join(codexDir, "hooks.json"), "utf8");
    try {
        JSON.parse(files["hooks.json"]);
    }
    catch {
        throw new Error("Invalid JSON: codex/hooks.json");
    }
    files["rules/user.rules"] = fs.readFileSync(path.join(codexDir, "rules/user.rules"), "utf8");
    const baseRules = fs.readFileSync(path.join(root, "ai-rules/base/global.md"), "utf8");
    const agentRules = fs.readFileSync(path.join(root, "ai-rules/agents/codex.md"), "utf8");
    files["AGENTS.md"] = baseRules + (agentRules.trim() ? `\n---\n\n${agentRules}` : "") + "\n";
    return files;
}
function planChanges(home, desired, previous, kind) {
    const changes = [];
    for (const [name, source] of Object.entries(desired)) {
        checkTarget(home, name);
        const before = readOptional(path.join(home, name));
        const legacyName = `${kind}_${name}`;
        const legacy = name !== "config.toml" && name.endsWith(".config.toml") && previous && previous.version < 3 && previous.files[legacyName] !== undefined;
        const old = previous?.files[legacy ? legacyName : name];
        let sourceFile;
        let currentText = before;
        if (legacy && before === undefined) {
            checkTarget(home, legacyName);
            currentText = readOptional(path.join(home, legacyName));
            if (currentText !== undefined) {
                assertProvider(readToml(currentText, legacyName), legacyName, kind);
                sourceFile = { name: legacyName, before: currentText };
            }
        }
        if (before !== undefined && (old === undefined || legacy)) {
            throw new Error(`Refusing to overwrite an unmanaged file: ${path.join(home, name)}`);
        }
        let after = source;
        if (name.endsWith(".toml") && currentText !== undefined) {
            const current = readToml(currentText, path.join(home, sourceFile?.name ?? name));
            const merged = mergeLocal(readToml(old, `previous ${name}`), current, readToml(source, name), name, sourceFile !== undefined);
            if (name === "config.toml") {
                const expected = readToml(source, name);
                const providers = expected.model_providers;
                assertProvider(merged, name, kind, providers?.azure?.env_key);
            }
            else if (["model_provider", "model_providers", "forced_login_method", "forced_chatgpt_workspace_id", "cli_auth_credentials_store", "openai_base_url", "chatgpt_base_url", "log_dir", "sqlite_home"].some(key => merged[key] !== undefined)) {
                throw new Error(`Provider or credential isolation cannot be overridden by a model profile: ${name}`);
            }
            after = (0, node_util_1.isDeepStrictEqual)(current, merged) ? currentText : (0, smol_toml_1.stringify)(merged);
        }
        else if (before !== undefined) {
            after = mergeLocal(old, before, source, name);
        }
        if (after !== before)
            changes.push({ name, before, after, ...(sourceFile ? { source: sourceFile } : {}) });
    }
    return changes;
}
function applyChanges(home, changes, kind) {
    if (changes.length === 0)
        return;
    fs.mkdirSync(home, { recursive: true, mode: 0o700 });
    const stage = fs.mkdtempSync(path.join(home, `.dotfiles-${kind}-stage-`));
    const applied = [];
    const sources = changes.flatMap(item => item.source ? [item.source] : []);
    let backup;
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
            if (change.source) {
                checkTarget(home, change.source.name);
                if (readOptional(path.join(home, change.source.name)) !== change.source.before)
                    throw new Error(`Migration source changed during generation: ${change.source.name}`);
            }
        }
        if (changes.some(change => change.before !== undefined)) {
            const backups = `.dotfiles-${kind}-backups`;
            checkTarget(home, `${backups}/placeholder`);
            fs.mkdirSync(path.join(home, backups), { recursive: true, mode: 0o700 });
            backup = fs.mkdtempSync(path.join(home, `${backups}/update-`));
            for (const change of changes) {
                if (change.before === undefined)
                    continue;
                const file = path.join(backup, change.name);
                fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
                fs.writeFileSync(file, change.before, { mode: 0o600 });
            }
        }
        for (let index = 0; index < changes.length; index++) {
            const change = changes[index];
            const file = path.join(home, change.name);
            for (const source of sources) {
                checkTarget(home, source.name);
                if (readOptional(path.join(home, source.name)) !== source.before)
                    throw new Error(`Migration source changed during generation: ${source.name}`);
            }
            fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
            checkTarget(home, change.name);
            if (readOptional(file) !== change.before)
                throw new Error(`Target changed during generation: ${file}`);
            fs.renameSync(path.join(stage, `${index}.new`), file);
            applied.push(change);
        }
    }
    catch (error) {
        for (const change of applied.reverse()) {
            const file = path.join(home, change.name);
            checkTarget(home, change.name);
            if (readOptional(file) !== change.after) {
                throw new Error(`Rollback stopped because a target changed: ${file}. Backup: ${backup ?? stage}`);
            }
            if (change.before === undefined)
                fs.unlinkSync(file);
            else {
                const restore = path.join(stage, "restore");
                fs.writeFileSync(restore, change.before, { mode: 0o600 });
                fs.renameSync(restore, file);
            }
        }
        throw error;
    }
    finally {
        // Only remove temporary files created by this invocation.
        for (const name of fs.readdirSync(stage))
            fs.unlinkSync(path.join(stage, name));
        fs.rmdirSync(stage);
    }
    if (backup)
        console.log(`Previous managed files backed up in ${backup}`);
}
function main(args = process.argv.slice(2)) {
    let requestedProvider;
    let env;
    let profile;
    let baseUrl;
    let apiVersion;
    let apiKeyEnv;
    let azureOption = false;
    let dryRun = process.env.SETUP_DRY_RUN === "1";
    for (let index = 0; index < args.length; index++) {
        if (args[index] === "--help" || args[index] === "-h") {
            console.log("Usage: ./setup.sh codex [--env ENV] [--provider azure|openai|chatgpt] [--base-url BASE_URL] [--api-version VERSION|none] [--api-key-env NAME] [--profile PROFILE] [--dry-run]\n" +
                "Generate an independent Codex environment from shared settings and model/effort profiles.\n" +
                "azure/openai retain ~/.codex-azure and ~/.codex-openai; other names use ~/.codex-envs/ENV.\n" +
                "Without --env, the environment defaults to the provider (azure for compatibility).\n" +
                "A new arbitrary environment requires --provider; later runs reuse its provider, connection and default profile.\n" +
                "Azure requires a URL on first generation. ChatGPT creates a fresh subscription environment without logging in.\n" +
                "OpenAI defaults to https://api.openai.com/v1 and uses OPENAI_API_KEY with API-only login.\n" +
                "Later runs reuse the saved connection and profile for the selected provider.\n" +
                "--api-version is Azure-only; omit it initially to leave api-version unset, or use 'none' to remove it.\n" +
                "--api-key-env selects an Azure key variable (default AZURE_OPENAI_API_KEY); keys themselves are never read or saved.\n" +
                "--azure-base-url and --azure-api-version remain available as Azure-only aliases.");
            return;
        }
        if (args[index] === "--dry-run")
            dryRun = true;
        else if (["--env", "--provider", "--profile", "--base-url", "--api-version", "--api-key-env", "--azure-base-url", "--azure-api-version"].includes(args[index])) {
            const option = args[index];
            const value = args[++index];
            if (!value || value.startsWith("--"))
                throw new Error(`${option} requires a value`);
            if (option.startsWith("--azure-"))
                azureOption = true;
            if (option === "--provider") {
                if (value !== "azure" && value !== "openai" && value !== "chatgpt")
                    throw new Error("--provider must be azure, openai or chatgpt");
                requestedProvider = value;
            }
            else if (option === "--env") {
                if (env && env !== value)
                    throw new Error("Environment specified twice with different names");
                env = value;
            }
            else if (option === "--profile")
                profile = value;
            else if (option === "--api-key-env")
                apiKeyEnv = value;
            else if (option === "--base-url" || option === "--azure-base-url")
                baseUrl = value;
            else
                apiVersion = value;
        }
        else
            throw new Error("Unknown codex setup argument; see --help");
    }
    env ??= requestedProvider ?? "azure";
    if (!validEnv(env))
        throw new Error("Invalid or reserved Codex environment name");
    if (env === "default")
        throw new Error("default uses the existing ~/.codex setup; choose a named environment to generate an independent home");
    const root = path.resolve(process.env.SETUP_DOTFILES_ROOT || path.join(__dirname, ".."));
    const home = envHome(path.resolve(process.env.SETUP_HOME || os.homedir()), env);
    const { text, baseline, kind: savedProvider } = readBaseline(home, env);
    if (requestedProvider && savedProvider && requestedProvider !== savedProvider) {
        throw new Error("An existing environment's provider cannot be changed; create a separate environment");
    }
    const kind = requestedProvider ?? savedProvider ?? (env === "azure" || env === "openai" ? env : undefined);
    if (!kind)
        throw new Error("A new named environment requires --provider azure|openai|chatgpt");
    if (kind === "openai" && (azureOption || apiVersion !== undefined || apiKeyEnv !== undefined)) {
        throw new Error("Azure connection options and --api-version cannot be used with --provider openai");
    }
    if (kind === "chatgpt" && (baseUrl !== undefined || apiVersion !== undefined || apiKeyEnv !== undefined || azureOption)) {
        throw new Error("ChatGPT subscription environments do not accept API connection options");
    }
    profile ??= baseline?.defaultProfile ?? profileCatalog(root, kind).defaultProfile;
    const legacyPrefix = /^(azure|openai)_/.exec(profile);
    if (legacyPrefix) {
        if (legacyPrefix[1] !== kind)
            throw new Error("Legacy profile provider does not match the selected environment");
        profile = profile.slice(legacyPrefix[0].length);
    }
    if (!/^[A-Za-z0-9_-]+$/.test(profile)) {
        throw new Error("Expected a model profile name without .config.toml");
    }
    const provider = kind === "azure" ? resolveAzureProvider(baseline, baseUrl, apiVersion, apiKeyEnv) : kind === "openai" ? resolveOpenAIProvider(baseline, baseUrl) : {};
    const desired = desiredFiles(root, profile, kind, provider);
    const changes = planChanges(home, desired, baseline, kind);
    const metadata = {
        version: 3, env, provider: kind, defaultProfile: profile,
        ...(kind === "azure" ? { azureProvider: provider } : kind === "openai" ? { openaiProvider: provider } : {}),
        files: desired,
    };
    const after = JSON.stringify(metadata, null, 2) + "\n";
    if (after !== text)
        changes.push({ name: markerName(), before: text, after });
    for (const change of changes)
        console.log(`${dryRun ? "Would write" : "Updating"} ${path.join(home, change.name)}`);
    if (dryRun)
        return;
    applyChanges(home, changes, kind);
    console.log(`Codex environment ${env} (${providerNames[kind]}) ${changes.length ? "generated" : "already up to date"}: ${home} (${profile})`);
}
if (require.main === module) {
    try {
        main();
    }
    catch (error) {
        // Avoid printing parser output or config values from nested errors.
        console.error(`codex setup: ${error instanceof Error ? error.message : "Generation failed"}`);
        process.exitCode = 1;
    }
}
