'use strict';

/**
 * Lark docx block 树 → Markdown。
 * 块类型参考：https://open.larksuite.com/document/server-docs/docs/docs/docx-v1/data-structure/block
 */

const BLOCK_TYPE = {
  PAGE: 1,
  TEXT: 2,
  HEADING1: 3,
  HEADING9: 11,
  BULLET: 12,
  ORDERED: 13,
  CODE: 14,
  QUOTE: 15,
  TODO: 17,
  CALLOUT: 19,
  DIVIDER: 22,
  IMAGE: 27,
  TABLE: 31,
  TABLE_CELL: 32,
  QUOTE_CONTAINER: 34,
};

// Lark 代码块的 language 是数字枚举，这里只列常用的，未命中则不标语言。
const CODE_LANGUAGE = {
  1: 'plaintext', 8: 'bash', 9: 'c', 10: 'cpp', 11: 'csharp', 12: 'css',
  17: 'diff', 22: 'go', 23: 'graphql', 24: 'html', 27: 'java', 28: 'javascript',
  29: 'json', 30: 'kotlin', 34: 'lua', 37: 'markdown', 43: 'nginx', 46: 'objectivec',
  49: 'php', 51: 'powershell', 53: 'python', 55: 'ruby', 56: 'rust', 58: 'scala',
  60: 'shell', 61: 'sql', 62: 'swift', 66: 'typescript', 71: 'xml', 72: 'yaml',
};

// 块类型 → 取哪个字段拿 elements。同名字段占绝大多数，少数需要特判。
const ELEMENT_FIELD = {
  [BLOCK_TYPE.PAGE]: 'page',
  [BLOCK_TYPE.TEXT]: 'text',
  [BLOCK_TYPE.BULLET]: 'bullet',
  [BLOCK_TYPE.ORDERED]: 'ordered',
  [BLOCK_TYPE.CODE]: 'code',
  [BLOCK_TYPE.QUOTE]: 'quote',
  [BLOCK_TYPE.TODO]: 'todo',
};

const escapeText = (raw) => String(raw == null ? '' : raw).replace(/([*_`[\]])/g, '\\$1');

/** 链接可能不是合法 URI 编码，解码失败时原样返回。 */
const safeDecode = (url) => {
  try {
    return decodeURIComponent(url);
  } catch (err) {
    return url;
  }
};

/** 渲染单个 text_run 的行内样式。接收 text_run 本身，不是外层 element。 */
const renderTextRun = (run) => {
  // 实测接口返回的字段是 text_element_style；text_style 是部分文档里的写法，一并兼容
  const style = run.text_element_style || run.text_style || {};
  const raw = run.content == null ? '' : String(run.content);
  const content = style.inline_code ? raw : escapeText(raw);

  const decorated = [
    [style.inline_code, (s) => '`' + s + '`'],
    [style.bold, (s) => '**' + s + '**'],
    [style.italic, (s) => '*' + s + '*'],
    [style.strikethrough, (s) => '~~' + s + '~~'],
  ].reduce((acc, [enabled, wrap]) => (enabled ? wrap(acc) : acc), content);

  const link = style.link && style.link.url;
  return link ? '[' + decorated + '](' + safeDecode(link) + ')' : decorated;
};

/** 渲染 elements 数组；非 text_run 的元素降级为可读占位。 */
const renderElements = (elements) =>
  (elements || [])
    .map((el) => {
      if (el.text_run) return renderTextRun(el.text_run);
      if (el.equation) return '$' + (el.equation.content || '').trim() + '$';
      if (el.mention_user) return '@' + (el.mention_user.user_id || 'user');
      if (el.mention_doc) return '[' + (el.mention_doc.title || 'doc') + '](' + (el.mention_doc.url || '') + ')';
      if (el.inline_file) return '[附件]';
      if (el.reminder) return '[提醒]';
      return '';
    })
    .join('');

/** 取出块自身的文本内容（不含子块）。 */
const textOf = (block) => {
  const field = ELEMENT_FIELD[block.block_type];
  const holder = field ? block[field] : null;
  if (holder && holder.elements) return renderElements(holder.elements);

  // 兜底：任何带 elements 的字段都认（覆盖 heading1-9 等未显式列出的类型）
  const fallback = Object.keys(block).find((k) => block[k] && Array.isArray(block[k].elements));
  return fallback ? renderElements(block[fallback].elements) : '';
};

const headingPrefix = (blockType) => {
  const level = blockType - BLOCK_TYPE.HEADING1 + 1; // 3 → h1
  return '#'.repeat(Math.min(level + 1, 6)) + ' '; // page 占用 #，正文标题从 ## 起
};

const isHeading = (t) => t >= BLOCK_TYPE.HEADING1 && t <= BLOCK_TYPE.HEADING9;

/**
 * 把一个块渲染成若干行。
 * @returns {{lines: string[], childIndent: string, childPrefix: string}}
 */
const renderBlock = (block, ctx) => {
  const t = block.block_type;
  const raw = textOf(block);
  // 行内文本块首尾自带的换行会渲染成多余空行；代码块必须原样保留
  const text = t === BLOCK_TYPE.CODE ? raw : raw.replace(/^\n+|\n+$/g, '');

  if (t === BLOCK_TYPE.PAGE) return { lines: ['# ' + text, ''], childIndent: '', childPrefix: '' };
  if (isHeading(t)) return { lines: ['', headingPrefix(t) + text, ''], childIndent: '', childPrefix: '' };
  if (t === BLOCK_TYPE.DIVIDER) return { lines: ['', '---', ''], childIndent: '', childPrefix: '' };

  if (t === BLOCK_TYPE.BULLET) {
    return { lines: ['- ' + text], childIndent: '  ', childPrefix: '' };
  }
  if (t === BLOCK_TYPE.ORDERED) {
    return { lines: [ctx.ordinal + '. ' + text], childIndent: '   ', childPrefix: '' };
  }
  if (t === BLOCK_TYPE.TODO) {
    const done = block.todo && block.todo.style && block.todo.style.done;
    return { lines: ['- [' + (done ? 'x' : ' ') + '] ' + text], childIndent: '  ', childPrefix: '' };
  }
  if (t === BLOCK_TYPE.CODE) {
    const lang = CODE_LANGUAGE[(block.code && block.code.style && block.code.style.language) || 0] || '';
    return { lines: ['', '```' + lang, text, '```', ''], childIndent: '', childPrefix: '' };
  }
  if (t === BLOCK_TYPE.QUOTE) {
    return { lines: ['> ' + text], childIndent: '', childPrefix: '> ' };
  }
  if (t === BLOCK_TYPE.QUOTE_CONTAINER) {
    // 容器自身无文本，内容全在子块里，靠 childPrefix 把子块变成引用
    return { lines: [], childIndent: '', childPrefix: '> ' };
  }
  if (t === BLOCK_TYPE.CALLOUT) {
    return { lines: ['', '> [!NOTE]'], childIndent: '', childPrefix: '> ' };
  }
  if (t === BLOCK_TYPE.IMAGE) {
    const token = (block.image && block.image.token) || '';
    return { lines: ['', '![图片](lark-image:' + token + ')', ''], childIndent: '', childPrefix: '' };
  }
  if (t === BLOCK_TYPE.TABLE) {
    // 表格是嵌套块，这里只标记位置，避免静默丢内容
    return { lines: ['', '<!-- Lark 表格（block ' + block.block_id + '），暂未转换 -->', ''], childIndent: '', childPrefix: '' };
  }
  if (t === BLOCK_TYPE.TEXT) {
    return { lines: text ? [text, ''] : [], childIndent: '', childPrefix: '' };
  }

  // 未知类型：能取到文本就输出，并留痕说明，绝不静默吞掉
  return {
    lines: text ? [text, '', '<!-- 未知块类型 ' + t + ' 已降级为纯文本 -->', ''] : ['<!-- 未知块类型 ' + t + '（无文本） -->'],
    childIndent: '',
    childPrefix: '',
  };
};

/** 深度优先遍历块树。 */
const walk = (blockId, blockMap, prefix, indent, out) => {
  const block = blockMap.get(blockId);
  if (!block) return;

  const children = block.children || [];
  let ordinal = 1;

  const rendered = renderBlock(block, { ordinal });
  rendered.lines.forEach((line) => out.push(line ? prefix + indent + line : prefix.trimEnd()));

  const childPrefix = prefix + rendered.childPrefix;
  const childIndent = indent + rendered.childIndent;

  children.forEach((childId) => {
    const child = blockMap.get(childId);
    if (child && child.block_type === BLOCK_TYPE.ORDERED) {
      const r = renderBlock(child, { ordinal });
      r.lines.forEach((line) => out.push(line ? childPrefix + childIndent + line : childPrefix.trimEnd()));
      ordinal += 1;
      (child.children || []).forEach((g) => walk(g, blockMap, childPrefix, childIndent + '   ', out));
      return;
    }
    ordinal = 1;
    walk(childId, blockMap, childPrefix, childIndent, out);
  });
};

/** 折叠连续空行。 */
const collapseBlankLines = (lines) =>
  lines.filter((line, i, arr) => !(line.trim() === '' && (arr[i - 1] || '').trim() === ''));

/**
 * 引用块内的空行会渲染成孤立的 ">"。若它已是引用的最后一行，
 * 换成真正的空行——既收尾了引用块，又给后面的段落留出分隔。
 */
const normalizeQuoteTails = (lines) =>
  lines.map((line, i, arr) => {
    if (line.trim() !== '>') return line;
    const next = arr[i + 1];
    const nextIsQuote = next !== undefined && next.trimStart().startsWith('>');
    return nextIsQuote ? line : '';
  });

/**
 * @param {Array} items /blocks 接口返回的 items
 * @returns {string} markdown
 */
const blocksToMarkdown = (items) => {
  if (!Array.isArray(items) || items.length === 0) return '';

  const blockMap = new Map(items.map((b) => [b.block_id, b]));
  const root = items.find((b) => b.block_type === BLOCK_TYPE.PAGE) || items[0];

  const out = [];
  walk(root.block_id, blockMap, '', '', out);
  return collapseBlankLines(normalizeQuoteTails(out)).join('\n').trimEnd() + '\n';
};

module.exports = { blocksToMarkdown, BLOCK_TYPE };
