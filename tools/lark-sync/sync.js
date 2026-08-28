#!/usr/bin/env node
'use strict';

/**
 * Lark 云文档 → 本地 Markdown 单向同步（只读，绝不写回远程）。
 *
 *   node sync.js pull            拉取 config.json 里的全部文档
 *   node sync.js pull <名称>      只拉取指定文档
 *   node sync.js status          对比本地与远程 revision，不写文件
 *   node sync.js watch [秒]       轮询 revision_id，有变化才重新拉取（默认 30 秒）
 */

const fs = require('fs');
const path = require('path');
const { LarkClient } = require('./lib/lark-client');
const { blocksToMarkdown } = require('./lib/blocks-to-markdown');

const ROOT = __dirname;
const CONFIG_PATH = path.join(ROOT, 'config.json');
const ENV_PATH = path.join(ROOT, '.env.local');
const STATE_PATH = path.join(ROOT, '.sync-state.local.json');
const DEFAULT_WATCH_INTERVAL_S = 30;
const MIN_WATCH_INTERVAL_S = 5;

const log = (...args) => console.log(...args);

/** 极简 .env 解析：KEY=VALUE，忽略注释与空行，不做变量插值。 */
const loadEnv = (file) => {
  if (!fs.existsSync(file)) {
    throw new Error('缺少凭证文件 ' + file + '\n请复制 .env.example 为 .env.local 并填入 App ID / Secret。');
  }
  return fs
    .readFileSync(file, 'utf8')
    .split(/\r?\n/)
    .filter((line) => line.trim() && !line.trim().startsWith('#'))
    .reduce((acc, line) => {
      const idx = line.indexOf('=');
      if (idx < 0) return acc;
      return { ...acc, [line.slice(0, idx).trim()]: line.slice(idx + 1).trim() };
    }, {});
};

/** 从 Lark 文档 URL 中提取 document_id。 */
const parseDocumentId = (urlOrId) => {
  const match = /\/(?:docx|docs)\/([A-Za-z0-9]+)/.exec(urlOrId);
  if (match) return match[1];
  if (/^[A-Za-z0-9]{20,}$/.test(urlOrId)) return urlOrId;
  throw new Error('无法从 "' + urlOrId + '" 解析出 document_id');
};

const loadConfig = () => {
  if (!fs.existsSync(CONFIG_PATH)) throw new Error('缺少配置文件 ' + CONFIG_PATH);
  const cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
  const docs = cfg.documents || [];
  if (docs.length === 0) throw new Error('config.json 的 documents 为空');

  return docs.map((doc) => ({
    name: doc.name,
    documentId: parseDocumentId(doc.url || doc.documentId),
    out: path.resolve(ROOT, doc.out),
    url: doc.url || '',
  }));
};

const readState = () => {
  if (!fs.existsSync(STATE_PATH)) return {};
  try {
    return JSON.parse(fs.readFileSync(STATE_PATH, 'utf8'));
  } catch (err) {
    log('⚠ 状态文件损坏，将重建:', err.message);
    return {};
  }
};

const writeState = (state) => fs.writeFileSync(STATE_PATH, JSON.stringify(state, null, 2));

const buildFrontMatter = (meta, doc) =>
  [
    '<!--',
    '  由 tools/lark-sync 自动生成，请勿直接编辑本文件——下次同步会被覆盖。',
    '  来源: ' + (doc.url || doc.documentId),
    '  标题: ' + meta.title,
    '  revision: ' + meta.revision_id,
    '  同步时间: ' + new Date().toISOString(),
    '-->',
    '',
  ].join('\n');

/** 拉取单个文档并写盘。返回是否发生了内容变化。 */
const pullOne = async (client, doc, state, { force }) => {
  const meta = await client.getDocumentMeta(doc.documentId);
  const previous = state[doc.documentId];
  const unchanged = previous && previous.revision === meta.revision_id && fs.existsSync(doc.out);

  if (unchanged && !force) {
    log('  = ' + doc.name + '  revision ' + meta.revision_id + ' 未变，跳过');
    return false;
  }

  const blocks = await client.getAllBlocks(doc.documentId);
  const markdown = buildFrontMatter(meta, doc) + blocksToMarkdown(blocks);

  fs.mkdirSync(path.dirname(doc.out), { recursive: true });
  fs.writeFileSync(doc.out, markdown, 'utf8');

  state[doc.documentId] = {
    name: doc.name,
    title: meta.title,
    revision: meta.revision_id,
    out: path.relative(ROOT, doc.out).replace(/\\/g, '/'),
    syncedAt: new Date().toISOString(),
  };

  const arrow = previous ? '↑ ' + previous.revision + ' → ' + meta.revision_id : '新建';
  log('  ✓ ' + doc.name + '  [' + arrow + ']  ' + blocks.length + ' 块 → ' + path.relative(process.cwd(), doc.out));
  return true;
};

const cmdPull = async (client, docs, { force }) => {
  const state = readState();
  log('拉取 ' + docs.length + ' 个文档…');

  const results = [];
  for (const doc of docs) {
    try {
      results.push(await pullOne(client, doc, state, { force }));
    } catch (err) {
      log('  ✗ ' + doc.name + '  ' + err.message);
      results.push(false);
    }
  }

  writeState(state);
  const changed = results.filter(Boolean).length;
  log(changed > 0 ? '完成：' + changed + ' 个有更新' : '完成：全部无变化');
  return changed;
};

const cmdStatus = async (client, docs) => {
  const state = readState();
  log('名称                  本地 rev   远程 rev   状态');

  for (const doc of docs) {
    const local = state[doc.documentId];
    try {
      const meta = await client.getDocumentMeta(doc.documentId);
      const localRev = local ? String(local.revision) : '—';
      const same = local && local.revision === meta.revision_id;
      const exists = local && fs.existsSync(doc.out);
      const status = !local ? '未拉取' : !exists ? '本地文件丢失' : same ? '已是最新' : '远程有更新';
      log(doc.name.padEnd(20) + '  ' + localRev.padEnd(8) + '   ' + String(meta.revision_id).padEnd(8) + '   ' + status);
    } catch (err) {
      log(doc.name.padEnd(20) + '  查询失败: ' + err.message);
    }
  }
};

const cmdWatch = async (client, docs, intervalS) => {
  const interval = Math.max(MIN_WATCH_INTERVAL_S, intervalS);
  log('轮询模式：每 ' + interval + ' 秒检查一次 revision，Ctrl+C 退出。');
  log('（只读同步——本地改动永远不会推回 Lark）\n');

  // 首次立即跑一遍，之后按间隔轮询
  for (;;) {
    const stamp = new Date().toLocaleTimeString('zh-CN');
    log('[' + stamp + ']');
    await cmdPull(client, docs, { force: false });
    await new Promise((resolve) => setTimeout(resolve, interval * 1000));
  }
};

const main = async () => {
  const [command = 'pull', ...rest] = process.argv.slice(2);

  const env = loadEnv(ENV_PATH);
  const client = new LarkClient({
    appId: env.LARK_APP_ID,
    appSecret: env.LARK_APP_SECRET,
    domain: env.LARK_DOMAIN,
  });

  const allDocs = loadConfig();
  const filter = rest.find((arg) => !arg.startsWith('-') && !/^\d+$/.test(arg));
  const docs = filter ? allDocs.filter((d) => d.name === filter) : allDocs;
  if (docs.length === 0) throw new Error('config.json 中找不到名为 "' + filter + '" 的文档');

  if (command === 'pull') return cmdPull(client, docs, { force: rest.includes('--force') });
  if (command === 'status') return cmdStatus(client, docs);
  if (command === 'watch') {
    const seconds = Number(rest.find((a) => /^\d+$/.test(a))) || DEFAULT_WATCH_INTERVAL_S;
    return cmdWatch(client, docs, seconds);
  }

  throw new Error('未知命令 "' + command + '"。可用：pull / status / watch');
};

main().catch((err) => {
  console.error('\n错误：' + err.message);
  process.exit(1);
});
