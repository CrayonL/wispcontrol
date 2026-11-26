<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=1024">
<meta name="referrer" content="same-origin">
<meta http-equiv="Cache-Control" content="no-store">
<title>WISP 无线上网 · TUF 6500</title>
<link rel="icon" href="/images/favicon.png">
<link rel="stylesheet" href="/index_style.css">
<link rel="stylesheet" href="/form_style.css">
<link rel="stylesheet" href="/res/softcenter.css">
<script src="/js/jquery.js"></script>
<script src="/state.js"></script>
<script src="/popup.js"></script>
<script src="/general.js"></script>
<script>
function menu_hook() {
  tabtitle[tabtitle.length - 1] = ['', 'WISP 无线上网', '__INHERIT__'];
  tablink[tablink.length - 1] = ['', 'Module_wispcontrol.asp', 'NULL'];
}
window.addEventListener('load', function () {
  document.body.setAttribute('skin', '<% nvram_get("sc_skin"); %>' || 'ASUSWRT');
  show_menu(menu_hook);
});
</script>
<style>
#wisp-control {padding:20px 0 24px}
#wisp-control .wisp-heading {display:flex;align-items:center;justify-content:space-between;gap:20px}
#wisp-control h1 {font-size:18px;margin:0}
#wisp-control .wisp-back {display:block;width:40px;height:40px;flex-shrink:0}
#wisp-control .wisp-back img {display:block;width:40px;height:40px;border:0}
#app #wisp-control .splitLine {margin:24px 0 10px 5px}
#wisp-control section {margin:16px 0}
#wisp-control p {margin:6px 0}
#wisp-control .FormTable {width:100%}
#wisp-control .FormTable td {overflow-wrap:anywhere}
#wisp-control .FormTable h2 {font:inherit;margin:0}
#wisp-control .FormTable th {width:35%}
#app #wisp-control .ks_btn,#app #wisp-control .button_gen {width:auto;white-space:nowrap;cursor:pointer}
#wisp-control .button_gen {min-width:122px}
#app #wisp-control button:disabled {opacity:.5;cursor:not-allowed}
#app #wisp-control .input_ss_table {width:300px;max-width:100%}
#wisp-control #networks {width:400px;max-width:100%}
#wisp-control .password-row {display:flex;align-items:center;gap:6px}
#wisp-control .password-row input {min-width:0}
#wisp-control .actions {display:flex;justify-content:center;flex-wrap:wrap;gap:10px;margin:20px 0}
#wisp-control :focus-visible {outline:2px solid #ffcc00;outline-offset:3px}
#wisp-control #message {position:sticky;top:0;z-index:2;background:#000;padding:6px 10px;white-space:pre-line}
#wisp-control #message.error {color:#ffb4ab}
</style>
<script type="module" src="/res/wisp_control.js?v=0.0.1"></script>
</head>
<body id="app" skin="ASUSWRT">
<div id="TopBanner"></div>
<div id="Loading" class="popup_bg"></div>
<table class="content" align="center" cellpadding="0" cellspacing="0"><tr>
<td width="17"></td>
<td valign="top" width="202"><div id="mainMenu"></div><div id="subMenu"></div></td>
<td valign="top">
<div id="tabMenu" class="submenuBlock"></div>
<table width="98%" align="left" cellpadding="0" cellspacing="0"><tr><td>
<table width="760" cellpadding="5" cellspacing="0" class="FormTitle" id="FormTitle"><tr><td bgcolor="#4D595D" valign="top">
<main id="wisp-control">
<header class="wisp-heading">
<h1 class="formfonttitle">软件中心 - WISP 无线上网</h1>
<a class="wisp-back" href="/Module_Softcenter.asp" aria-label="返回软件中心" title="返回软件中心"><img src="/images/backprev.png" alt="" onmouseover="this.src='/images/backprevclick.png'" onmouseout="this.src='/images/backprev.png'"></a>
</header>
<div class="splitLine"></div>
<p class="SimpleNote">通过上级 Wi-Fi 为本机热点和 LAN 口提供网络。更换上级网络时，本机的管理员账号、热点名称和密码保持不变。</p>
<p id="message" role="status" aria-live="polite">正在读取路由器状态…</p>
<section aria-labelledby="status-title">
<table class="FormTable" cellpadding="4" cellspacing="0">
<thead><tr><td colspan="2"><h2 id="status-title">当前连接</h2></td></tr></thead>
<tbody>
<tr><th scope="row">开机自动连接</th><td><span id="enabled">读取中</span></td></tr>
<tr><th scope="row">已保存的 Wi-Fi</th><td><span id="current-ssid">—</span></td></tr>
<tr><th scope="row">无线连接状态</th><td><span id="connection">—</span></td></tr>
<tr><th scope="row">上级分配的地址</th><td><span id="address">—</span></td></tr>
<tr><th scope="row">上一份 Wi-Fi 配置</th><td><span id="previous-ssid">—</span></td></tr>
<tr><th scope="row">状态操作</th><td><button class="ks_btn" id="refresh" type="button">刷新状态</button></td></tr>
</tbody></table>
<p class="SimpleNote">“已获取地址”表示已连上上级 Wi-Fi，不等同于外网检测通过。华硕首页仍可能显示“未连接网线”。</p>
</section>
<section aria-labelledby="connect-title">
<form id="connect-form">
<table class="FormTable" cellpadding="4" cellspacing="0">
<thead><tr><td colspan="2"><h2 id="connect-title">连接新的上级 Wi-Fi</h2></td></tr></thead>
<tbody>
<tr><td colspan="2"><p>此版本使用 2.4GHz、WPA2 个人密码网络。可扫描后选择，也可手动填写名称和信道。</p></td></tr>
<tr><th scope="row">附近网络</th><td><button class="ks_btn" id="scan" type="button">扫描附近 Wi-Fi</button><p id="scan-note">扫描通常需要几秒钟，不会更换已保存的连接。</p></td></tr>
<tr><th scope="row"><label for="networks">扫描结果</label></th><td><select class="input_option" id="networks"><option value="">请先扫描，或在下方手动填写</option></select></td></tr>
<tr><th scope="row"><label for="ssid">新 Wi-Fi 名称（SSID）</label></th><td><input class="input_ss_table" id="ssid" autocomplete="off" required aria-describedby="network-help"></td></tr>
<tr><th scope="row"><label for="channel">2.4GHz 信道</label></th><td><select class="input_option" id="channel" required><option value="">请选择</option></select></td></tr>
<tr><th scope="row"><label for="password">新 Wi-Fi 密码</label></th><td><div class="password-row"><input class="input_ss_table" id="password" type="password" autocomplete="new-password" required minlength="8" maxlength="63" aria-describedby="password-help"><button class="ks_btn" id="show-password" type="button" aria-pressed="false">显示</button></div><p id="password-help">8–63 个英文字母、数字或可打印符号；旧密码不会显示在页面里。</p></td></tr>
</tbody></table>
<p id="network-help" class="SimpleNote">连接时会同步本机 2.4GHz 热点信道，并重启约 1–2 分钟。上级以后更换信道时，请重新扫描并应用。</p>
<p class="SimpleNote">上级网络的网段需与本机 LAN（192.168.50.0/24）不同。此页暂不处理需要网页登录或企业账号认证的网络。</p>
<div class="apply_gen"><button class="button_gen" id="connect" type="submit">保存新 Wi-Fi 并重启连接</button></div>
</form>
</section>
<section aria-labelledby="recover-title">
<table class="FormTable" cellpadding="4" cellspacing="0">
<thead><tr><td colspan="2"><h2 id="recover-title">恢复或停用</h2></td></tr></thead>
<tbody><tr><td colspan="2"><p>更换 Wi-Fi 后保留上一份配置。若新网络连接失败，仍可通过本机热点或 LAN 口打开此页，恢复上一份配置。</p>
<div class="actions"><button class="button_gen" id="previous" type="button" disabled>恢复上一份 Wi-Fi 并重启</button><button class="button_gen" id="enable" type="button" disabled>启用 WISP 并重启</button><button class="button_gen" id="disable" type="button" disabled>停用 WISP 并重启</button></div>
<p>停用后恢复普通无线路由器使用，需要 WAN 口接入有效上网线路。已保存的上级 Wi-Fi 和本机账号、热点设置会保留。</p>
</td></tr></tbody></table>
</section>
</main>
</td></tr></table>
</td></tr></table>
</td><td width="10"></td>
</tr></table>
<div id="footer"></div>
</body>
</html>
