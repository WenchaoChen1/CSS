#!/usr/bin/env node
'use strict';

/**
 * 走 Lark OAuth 拿 user_access_token（个人身份），存到 .user-token.local.json。
 *
 *   node authorize.js
 *
 * 前置：应用安全设置里的重定向 URL 必须包含 http://localhost:3001/callback
 * 与 lark-mcp 的 --oauth 不同，这里给出的是 Lark 官方授权页链接，不会 60 秒过期。
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 3001;
const CALLBACK_PATH = '/callback';
const REDIRECT_URI = 'http://localhost:' + PORT + CALLBACK_PATH;
const TOKEN_FILE = path.join(__dirname, '.user-token.local.json');
const ENV_PATH = path.join(__dirname, '.env.local');

const loadEnv = () =>
  fs
    .readFileSync(ENV_PATH, 'utf8')
    .split(/\r?\n/)
    .filter((l) => l.trim() && !l.trim().startsWith('#'))
    .reduce((acc, line) => {
      const i = line.indexOf('=');
      return i < 0 ? acc : { ...acc, [line.slice(0, i).trim()]: line.slice(i + 1).trim() };
    }, {});

const env = loadEnv();
const APP_ID = env.LARK_APP_ID;
const APP_SECRET = env.LARK_APP_SECRET;
const DOMAIN = (env.LARK_DOMAIN || 'https://open.larksuite.com').replace(/\/$/, '');

const buildAuthUrl = (state) =>
  DOMAIN +
  '/open-apis/authen/v1/authorize?app_id=' +
  encodeURIComponent(APP_ID) +
  '&redirect_uri=' +
  encodeURIComponent(REDIRECT_URI) +
  '&state=' +
  encodeURIComponent(state);

/** 用回调拿到的 code 换 user_access_token。 */
const exchangeToken = async (code) => {
  const res = await fetch(DOMAIN + '/open-apis/authen/v2/oauth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      grant_type: 'authorization_code',
      client_id: APP_ID,
      client_secret: APP_SECRET,
      code,
      redirect_uri: REDIRECT_URI,
    }),
  });
  const body = await res.json();
  if (body.code !== 0) throw new Error('换取 token 失败: ' + JSON.stringify(body).slice(0, 300));
  return body;
};

const fetchUserInfo = async (accessToken) => {
  const res = await fetch(DOMAIN + '/open-apis/authen/v1/user_info', {
    headers: { Authorization: 'Bearer ' + accessToken },
  });
  const body = await res.json();
  return body.code === 0 ? body.data : null;
};

const replyHtml = (res, title, detail) => {
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(
    '<html><head><meta charset="utf-8"><title>' + title + '</title></head>' +
      '<body style="font-family:system-ui;padding:60px;text-align:center">' +
      '<h2>' + title + '</h2><p style="color:#666">' + detail + '</p>' +
      '<p style="color:#999;font-size:14px">可以关闭本页面，回到 Claude Code。</p></body></html>'
  );
};

const state = 'auth_' + APP_ID.slice(-8);

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost:' + PORT);
  if (url.pathname !== CALLBACK_PATH) {
    res.writeHead(404).end('not found');
    return;
  }

  const code = url.searchParams.get('code');
  if (!code) {
    replyHtml(res, '❌ 授权失败', '回调里没有 code：' + (url.searchParams.get('error') || '未知原因'));
    console.log('回调缺少 code，未完成授权');
    return;
  }

  try {
    const token = await exchangeToken(code);
    const info = await fetchUserInfo(token.access_token);

    fs.writeFileSync(
      TOKEN_FILE,
      JSON.stringify(
        {
          access_token: token.access_token,
          refresh_token: token.refresh_token,
          expires_in: token.expires_in,
          obtained_at: new Date().toISOString(),
          user: info ? { name: info.name, en_name: info.en_name, open_id: info.open_id } : null,
        },
        null,
        2
      )
    );

    const who = info ? info.name + (info.en_name ? ' (' + info.en_name + ')' : '') : '未知用户';
    replyHtml(res, '✅ 授权成功', '已获取 ' + who + ' 的访问令牌。');
    console.log('AUTH_SUCCESS');
    console.log('授权用户: ' + who);
    console.log('token 有效期: ' + token.expires_in + ' 秒');
    console.log('已保存到: ' + TOKEN_FILE);
    setTimeout(() => { server.close(); process.exit(0); }, 500);
  } catch (err) {
    replyHtml(res, '❌ 换取令牌失败', err.message);
    console.log('ERROR ' + err.message);
    setTimeout(() => { server.close(); process.exit(1); }, 500);
  }
});

server.listen(PORT, () => {
  console.log('AUTH_URL');
  console.log(buildAuthUrl(state));
  console.log('等待授权回调中（本服务监听 ' + REDIRECT_URI + '）…');
});

setTimeout(() => { console.log('10 分钟未完成授权，退出'); server.close(); process.exit(1); }, 600000);
