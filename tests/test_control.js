'use strict';
const assert = require('node:assert/strict');
const control = require('../wispcontrol/res/wisp_control.js');
const scan = `BSS aa:bb:cc:dd:ee:ff(on ath0)
\tfreq: 2437
\tsignal: -45.00 dBm
\tSSID: DEMO1
\tRSN: * Version: 1
\t\t * Pairwise ciphers: TKIP CCMP
\t\t * Authentication suites: PSK
BSS aa:bb:cc:dd:ee:00(on ath0)
\tfreq: 2412
\tsignal: -55.00 dBm
\tSSID: \\xe4\\xb8\\xad\\xe6\\x96\\x87
\tRSN: * Version: 1
\t\t * Pairwise ciphers: CCMP
\t\t * Authentication suites: SAE
BSS aa:bb:cc:dd:ee:01(on ath0)
\tfreq: 5180
\tsignal: -35.00 dBm
\tSSID: 5GHz
`;
const networks = control.parseScan(scan);
assert.equal(networks.length, 2);
assert.equal(networks[0].channel, 6);
assert.equal(networks[0].supported, true);
assert.equal(networks[1].ssid, '中文');
assert.equal(networks[1].supported, false);
assert.equal(control.fromHex(control.escapedSsidHex('a\\\\b')), 'a\\b');
assert.equal(control.hexBytes('中文'), 'e4b8ade69687');
assert.deepEqual(control.validateNetwork({ssid:'DEMO1',password:'abcdefgh',channel:'1'}), ['44454d4f31','6162636465666768','1']);
assert.throws(() => control.validateNetwork({ssid:'中'.repeat(11),password:'abcdefgh',channel:'1'}));
assert.throws(() => control.validateNetwork({ssid:'DEMO1',password:'abc\ndefgh',channel:'1'}));
assert.throws(() => control.validateNetwork({ssid:'DEMO1',password:'abcdefgh',channel:'14'}));
assert.equal(control.fromHex(control.hexBytes('<script>alert(1)</script>')), '<script>alert(1)</script>');
console.log('PASS: scan parsing, Chinese SSIDs, authentication filtering, input validation');
