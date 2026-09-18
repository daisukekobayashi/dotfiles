const { readFileSync } = require('node:fs');
const { spawnSync } = require('node:child_process');
const path = require('node:path');

// Claude Code supplies session data as JSON on stdin.
const data = JSON.parse(readFileSync(0, 'utf8'));
const dir = data.workspace?.current_dir ?? data.cwd ?? '';
const model = data.model?.display_name ?? 'Claude';
const effort = data.effort?.level;
const used = data.context_window?.used_percentage;

function git(...args) {
  const result = spawnSync('git', ['--no-optional-locks', '-C', dir, ...args], {
    encoding: 'utf8',
    windowsHide: true,
    timeout: 1000,
  });
  return result.status === 0 ? result.stdout.trim() : null;
}

let branch = '';
if (dir && git('rev-parse', '--is-inside-work-tree') === 'true') {
  branch = git('symbolic-ref', '--quiet', '--short', 'HEAD')
    || git('rev-parse', '--short', 'HEAD') || '';
  if (branch && git('status', '--porcelain', '--untracked-files=normal')) {
    branch += '*';
  }
}

const limits = data.rate_limits;
const windows = [];
for (const [key, label] of [['five_hour', '5h'], ['seven_day', '7d']]) {
  const percentage = limits?.[key]?.used_percentage;
  if (percentage != null) windows.push(`${label} ${Math.floor(percentage)}%`);
}
const usage = [];
if (windows.length) usage.push(`usage ${windows.join(' / ')}`);
const spend = limits?.spend_limit?.used_percentage;
if (spend != null) usage.push(`spend ${Math.floor(spend)}%`);

const displayDir = path.basename(dir) || dir || '~';
const location = `\x1b[01;34m${displayDir}\x1b[00m${branch ? ` (${branch})` : ''}`;
const modelLabel = effort ? `${model} / ${effort}` : model;
console.log(`${location} [${modelLabel}] | ctx ${used == null ? '--' : Math.floor(used)}% | ${usage.join(' | ') || 'usage --'}`);
