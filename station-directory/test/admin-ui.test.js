import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';

test('main station results drive shared artwork selection',async()=>{
 const [html,script]=await Promise.all([
  fs.readFile('public/admin/index.html','utf8'),
  fs.readFile('public/admin/app.js','utf8')
 ]);
 assert.match(html,/id="select-page"/);
 assert.match(html,/id="shared-artwork-button" disabled/);
 assert.match(html,/id="selection-count"/);
 assert.match(script,/sharedSelection=new Map\(stationSelection\)/);
 assert.match(script,/stationSelection\.size>=100/);
 assert.match(script,/stationSelection\.clear\(\).*Artwork applied/s);
 assert.match(script,/data-test-stream/);
 assert.match(script,/New and changed streams are being tested automatically/);
});

test('network artwork uses the shared square crop editor',async()=>{
 const html=await fs.readFile('public/admin/index.html','utf8');
 const script=await fs.readFile('public/admin/app.js','utf8');
 assert.match(html,/id="network-artwork-button"/);
 assert.match(html,/id="network-artwork-dialog"/);
 assert.match(html,/id="network-artwork-file"/);
 assert.match(script,/loadCrop\(e\.target\.files\[0\],'network'\)/);
 assert.match(script,/X-Network-Version/);
});
