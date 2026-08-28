'use strict';

/** Lark 开放平台 API 薄封装：token 获取与缓存、分页拉取。无第三方依赖。 */

const TOKEN_SAFETY_MARGIN_MS = 60 * 1000; // 提前 1 分钟续期，避免边界过期
const REQUEST_TIMEOUT_MS = 30 * 1000;
const PAGE_SIZE = 500;

class LarkError extends Error {
  constructor(code, msg, logId) {
    super('Lark API ' + code + ': ' + msg + (logId ? ' (log_id=' + logId + ')' : ''));
    this.name = 'LarkError';
    this.code = code;
  }
}

const request = async (url, options) => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const res = await fetch(url, { ...options, signal: controller.signal });
    const body = await res.json();
    if (body.code !== 0) throw new LarkError(body.code, body.msg, body.error && body.error.log_id);
    return body.data;
  } catch (err) {
    if (err.name === 'AbortError') throw new Error('请求超时（' + REQUEST_TIMEOUT_MS / 1000 + 's）: ' + url);
    throw err;
  } finally {
    clearTimeout(timer);
  }
};

class LarkClient {
  constructor({ appId, appSecret, domain }) {
    if (!appId || !appSecret) throw new Error('缺少 appId / appSecret');
    this.appId = appId;
    this.appSecret = appSecret;
    this.domain = (domain || 'https://open.larksuite.com').replace(/\/$/, '');
    this.token = null;
    this.tokenExpiresAt = 0;
  }

  async getToken() {
    if (this.token && Date.now() < this.tokenExpiresAt) return this.token;

    const data = await request(this.domain + '/open-apis/auth/v3/tenant_access_token/internal', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ app_id: this.appId, app_secret: this.appSecret }),
    });
    // 这个接口把 token 平铺在响应根上，request() 返回的 data 可能为空
    const raw = data && data.tenant_access_token ? data : null;
    if (!raw) return this.getTokenFallback();

    this.token = raw.tenant_access_token;
    this.tokenExpiresAt = Date.now() + raw.expire * 1000 - TOKEN_SAFETY_MARGIN_MS;
    return this.token;
  }

  /** tenant_access_token 接口不遵循 {code,data} 包装，需单独解析。 */
  async getTokenFallback() {
    const res = await fetch(this.domain + '/open-apis/auth/v3/tenant_access_token/internal', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ app_id: this.appId, app_secret: this.appSecret }),
    });
    const body = await res.json();
    if (body.code !== 0) throw new LarkError(body.code, body.msg);
    this.token = body.tenant_access_token;
    this.tokenExpiresAt = Date.now() + body.expire * 1000 - TOKEN_SAFETY_MARGIN_MS;
    return this.token;
  }

  async authedGet(path) {
    const token = await this.getToken();
    return request(this.domain + path, { headers: { Authorization: 'Bearer ' + token } });
  }

  /** 文档元信息，含 title 与 revision_id。 */
  async getDocumentMeta(documentId) {
    const data = await this.authedGet('/open-apis/docx/v1/documents/' + documentId);
    return data.document;
  }

  /** 拉取全部块，自动翻页。 */
  async getAllBlocks(documentId) {
    const collected = [];
    let pageToken = '';

    do {
      const query = 'page_size=' + PAGE_SIZE + (pageToken ? '&page_token=' + encodeURIComponent(pageToken) : '');
      const data = await this.authedGet('/open-apis/docx/v1/documents/' + documentId + '/blocks?' + query);
      collected.push(...(data.items || []));
      pageToken = data.has_more ? data.page_token : '';
    } while (pageToken);

    return collected;
  }
}

module.exports = { LarkClient, LarkError };
