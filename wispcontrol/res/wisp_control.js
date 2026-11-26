'use strict';
const WISP_TIMEOUT_MS = 35000;
const WISP_REFRESH_MS = 15000;
const WISP_REBOOT_WAIT_MS = 90000;
// 沿用软件中心的 8 位请求 ID；此固件实测无法正确关联 9 位 ID 的回复。
const WISP_REQUEST_ID_LIMIT = 100000000;
let busy = false;
let currentStatus = null;
let scanned = [];
const byId = id => document.getElementById(id);

function hexBytes(text) {
  return Array.from(new TextEncoder().encode(text), byte => byte.toString(16).padStart(2, '0')).join('');
}

function fromHex(hex) {
  if (!/^(?:[0-9a-f]{2})*$/i.test(hex)) throw new Error('配置中的 Wi-Fi 名称格式错误。');
  return new TextDecoder().decode(Uint8Array.from(hex.match(/../g) || [], pair => parseInt(pair, 16)));
}

function escapedSsidHex(text) {
  const bytes = [];
  const escapes = {'n':10, 'r':13, 't':9, 'e':27, '\\':92, '"':34};
  for (let index = 0; index < text.length;) {
    const hex = text.slice(index).match(/^\\x([0-9a-f]{2})/i);
    if (hex) { bytes.push(parseInt(hex[1], 16)); index += 4; continue; }
    if (text[index] === '\\' && Object.hasOwn(escapes, text[index + 1])) {
      bytes.push(escapes[text[index + 1]]); index += 2; continue;
    }
    const point = String.fromCodePoint(text.codePointAt(index));
    bytes.push(...new TextEncoder().encode(point)); index += point.length;
  }
  return bytes.map(byte => byte.toString(16).padStart(2, '0')).join('');
}

function parseScan(raw) {
  return raw.split(/^BSS /m).slice(1).map(block => {
    const frequency = Number(block.match(/^\s*freq:\s*(\d+)/m)?.[1]);
    const name = block.match(/^[ \t]*SSID: (.*)$/m)?.[1] || '';
    const rsn = block.match(/^[ \t]*RSN:[^\n]*(?:\n[ \t]+\*[^\n]*)*/m)?.[0] || '';
    const ssidHex = escapedSsidHex(name);
    return {ssidHex, ssid:fromHex(ssidHex), channel:(frequency - 2407) / 5,
      signal:Number(block.match(/^\s*signal:\s*(-?[\d.]+)/m)?.[1]),
      supported:/Authentication suites:.*\bPSK\b/.test(rsn) && /Pairwise ciphers:.*\bCCMP\b/.test(rsn)};
  }).filter(net => Number.isInteger(net.channel) && net.channel >= 1 && net.channel <= 13 && net.ssidHex)
    .sort((first, second) => second.signal - first.signal);
}

function validateNetwork(fields) {
  const ssidHex = hexBytes(fields.ssid);
  if (ssidHex.length < 2 || ssidHex.length > 64) throw new Error('Wi-Fi 名称须为 1–32 字节，中文通常每字占 3 字节。');
  if (!/^[\x20-\x7e]{8,63}$/.test(fields.password)) throw new Error('密码须为 8–63 个可打印英文字符。');
  if (!/^(?:[1-9]|1[0-3])$/.test(fields.channel)) throw new Error('请选择正确的 2.4GHz 信道。');
  return [ssidHex, hexBytes(fields.password), fields.channel];
}

function message(text, error = false) {
  byId('message').textContent = text;
  byId('message').classList.toggle('error', error);
}

function setBusy(value) {
  busy = value;
  byId('wisp-control').querySelectorAll('button,input,select').forEach(control => { control.disabled = value; });
  byId('enable').disabled = value || !currentStatus?.ssidHex;
  byId('enable').textContent = currentStatus?.enabled ? '重新连接当前 Wi-Fi 并重启' : '启用 WISP 并重启';
  byId('disable').disabled = value || !currentStatus || !currentStatus.enabled;
  byId('previous').disabled = value || !currentStatus?.previousHex;
}

const ERROR_TEXT = {
  ambiguous_config:'检测到两套 WISP 配置，请先确认开机脚本使用的目录。',
  missing_config:'请先扫描或填写上级 Wi-Fi，保存第一份配置。',
  router_mode:'请将华硕保持在“无线路由器模式”。',
  status_failed:'无法读取无线状态，请稍后刷新。', invalid_action:'操作参数无效，请刷新页面。',
  busy:'另一个操作尚未结束，请稍后重试。', reboot_pending:'已提交重启，请等待路由器重新启动。',
  unfinished_transaction:'发现未完成的配置操作，已停止继续写入，请通过 SSH 检查事务备份。',
  storage_failed:'无法写入路由器存储，请检查剩余空间。', scan_failed:'扫描未完成，请稍后重试，或手动填写名称和信道。',
  lan_changed:'LAN 地址已变化，现有 WISP 脚本需要同步调整后才能使用。',
  invalid_profile:'网络参数无效，或没有可恢复的上一份配置。', backup_failed:'原配置备份失败，未应用更改。',
  apply_failed:'应用失败，原配置已还原，未重启。', rollback_failed:'应用及还原失败，事务备份已保留，请通过 SSH 检查。',
  pending_failed:'无法记录重启状态，原配置已还原，未重启。'
};

async function api(params) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), WISP_TIMEOUT_MS);
  try {
    const response = await fetch('/_api/', {method:'POST', credentials:'same-origin', signal:controller.signal,
      headers:{'Content-Type':'application/json'}, body:JSON.stringify({id:Math.floor(Math.random() * WISP_REQUEST_ID_LIMIT), method:'wisp_control.sh', params, fields:{}})});
    const envelope = await response.json();
    if (envelope.result === -403) throw new Error('后台登录已失效，请返回路由器后台重新登录。');
    if (!response.ok || typeof envelope.result !== 'string') throw new Error('后台返回异常，请刷新或重新登录。');
    const split = envelope.result.indexOf('|');
    const kind = envelope.result.slice(0, split);
    const payload = envelope.result.slice(split + 1);
    if (kind === 'error') throw new Error(ERROR_TEXT[payload] || '路由器拒绝操作，请检查配置。');
    return {kind, payload};
  } finally { clearTimeout(timer); }
}

function decodePayload(payload) {
  return new TextDecoder().decode(Uint8Array.from(atob(payload), character => character.charCodeAt(0)));
}

async function refresh() {
  const result = await api(['status']);
  if (result.kind !== 'status') throw new Error('路由器没有返回有效状态。');
  currentStatus = JSON.parse(decodePayload(result.payload));
  byId('enabled').textContent = !currentStatus.ssidHex ? '等待首次配置' : currentStatus.enabled ? '已启用' : '已停用';
  byId('current-ssid').textContent = fromHex(currentStatus.ssidHex) || '未配置';
  byId('previous-ssid').textContent = fromHex(currentStatus.previousHex) || '暂无（首次更换后保留）';
  byId('address').textContent = currentStatus.ip || '尚未获取';
  byId('connection').textContent = currentStatus.state === 'COMPLETED' ? '已连接上级 Wi-Fi' : currentStatus.state === 'STOPPED' ? '未运行' : '连接中或连接失败';
  if (currentStatus.state === 'COMPLETED' && currentStatus.hasRoute === false) {
    byId('connection').textContent = '已连接 Wi-Fi，但缺少上网路由；可重新连接当前 Wi-Fi';
  }
  if (currentStatus.pending) message('重启已提交。约 1–2 分钟后重新连接本机热点，或保持网线连接，再刷新此页。');
  setBusy(busy || currentStatus.pending);
}

async function scan() {
  setBusy(true); message('正在扫描 2.4GHz Wi-Fi…');
  try {
    const result = await api(['scan']);
    if (result.kind !== 'scan') throw new Error('扫描结果无效。');
    scanned = parseScan(decodePayload(result.payload));
    byId('networks').replaceChildren(new Option('请选择上级 Wi-Fi', ''));
    scanned.forEach((net, index) => {
      const option = new Option(`${net.ssid} · 信道 ${net.channel} · ${net.signal} dBm${net.supported ? '' : ' · 暂不支持此认证'}`, String(index));
      option.disabled = !net.supported; byId('networks').add(option);
    });
    byId('scan-note').textContent = `发现 ${scanned.length} 个 2.4GHz 网络。名称相同时，请按信道和信号选择。`;
    message(scanned.length ? '扫描完成，当前连接未更换。' : '未扫描到可显示的网络，可重试或手动填写。');
  } finally { setBusy(false); }
}

async function apply(params, prompt) {
  if (!window.confirm(prompt + '\n\n将重启路由器，联网会中断约 1–2 分钟。是否继续？')) return;
  setBusy(true); message('正在保存配置，请勿断电…');
  try {
    const result = await api(params);
    if (result.kind !== 'accepted') throw new Error('未收到路由器的操作确认，请刷新状态后再检查。');
    byId('password').value = '';
    message('配置已保存，路由器即将重启。约 1–2 分钟后重新连接本机热点，再刷新状态。');
    setTimeout(() => { setBusy(false); run(refresh); }, WISP_REBOOT_WAIT_MS);
  } catch (error) { setBusy(false); throw error; }
}

async function run(action) {
  try { await action(); }
  catch (error) { message(error.name === 'AbortError' ? '等待路由器响应超时。若刚执行了重启，请稍后刷新确认，不要连续提交。' : error.message, true); }
}

function initialize() {
  for (let channel = 1; channel <= 13; channel++) byId('channel').add(new Option(String(channel), String(channel)));
  byId('refresh').onclick = () => run(refresh);
  byId('scan').onclick = () => run(scan);
  byId('networks').onchange = event => {
    const net = scanned[Number(event.target.value)];
    if (event.target.value === '' || !net) return;
    byId('ssid').value = net.ssid; byId('channel').value = String(net.channel); byId('password').focus();
  };
  byId('show-password').onclick = () => {
    const showing = byId('password').type === 'password';
    byId('password').type = showing ? 'text' : 'password';
    byId('show-password').textContent = showing ? '隐藏' : '显示';
    byId('show-password').setAttribute('aria-pressed', String(showing));
  };
  byId('connect-form').onsubmit = event => {
    event.preventDefault(); run(() => {
      const params = validateNetwork({ssid:byId('ssid').value, password:byId('password').value, channel:byId('channel').value});
      return apply(['connect', ...params], `连接“${byId('ssid').value}”，并保留当前 Wi-Fi 作为上一份配置。`);
    });
  };
  byId('previous').onclick = () => run(() => apply(['previous'], '恢复上一份上级 Wi-Fi，并启用 WISP。'));
  byId('disable').onclick = () => run(() => apply(['disable'], '停用 WISP，恢复普通路由器使用。此后需要 WAN 口接入上网线路；已保存的 Wi-Fi 不会删除。'));
  byId('enable').onclick = () => run(() => apply(['enable'], '启用 WISP，连接已保存的上级 Wi-Fi。'));
  setBusy(false);
  run(async () => { await refresh(); if (!currentStatus.pending) message(currentStatus.ssidHex ? '状态已更新，当前配置未更改。' : '首次使用请扫描或填写上级 Wi-Fi，再保存并重启连接。'); });
  setInterval(() => { if (!busy) run(refresh); }, WISP_REFRESH_MS);
}

if (typeof document !== 'undefined') document.addEventListener('DOMContentLoaded', initialize);
if (typeof module !== 'undefined') module.exports = {hexBytes, fromHex, escapedSsidHex, parseScan, validateNetwork};
