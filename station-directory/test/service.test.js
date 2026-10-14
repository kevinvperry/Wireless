import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {Miniflare} from 'miniflare';
import bcrypt from 'bcryptjs';
let mf,db,admin,editor;
const origin='https://directory.example';
const call=(path,options={})=>mf.dispatchFetch(origin+path,options);
const request=(path,method,body,session,extra={})=>call(path,{method,headers:{'Content-Type':'application/json',Origin:origin,...(session?{Cookie:session.cookie,'X-CSRF-Token':session.csrf}:{}),...extra},body:JSON.stringify(body)});
async function signIn(email,password){const response=await request('/api/auth/login','POST',{email,password});const data=await response.json();assert.equal(response.status,200,JSON.stringify(data));return {cookie:response.headers.get('Set-Cookie').split(';')[0],csrf:data.csrf_token,user:data.user};}
const sample=()=>({name:'Test Radio',network:'Test Network',country:'AU',state:'VIC',cities:['Melbourne'],tags:['Sport'],frequency:'101.1 FM',tagline:'Test radio tagline',genres:['Talkback','Sport'],description:'A test service',website_url:'https://example.org',logo_url:'',contact:{talkback_phone:'1300 000 001',sms:'0400 000 001',office_phone:'(03) 9000 0001',email:'studio@example.org',address:'1 Test Street, Melbourne VIC 3000',contact_page:'https://example.org/contact'},status:'published',preferred_stream_id:'stream_test',editorial_notes:'Private note',streams:[{id:'stream_test',url:'https://example.org/audio.m3u8',label:'Main',format:'hls',enabled:true,request_headers:{}}]});
before(async()=>{
 mf=new Miniflare({modules:true,scriptPath:'.wrangler/test-build/index.js',compatibilityDate:'2026-06-03',d1Databases:['DB'],r2Buckets:['ARTWORK'],bindings:{AUTH_MODE:'password',STREAM_TESTING_DISABLED:'true'},serviceBindings:{ASSETS:()=>new Response('test asset')}});
 db=await mf.getD1Database('DB');
 for(const file of (await fs.readdir('migrations')).sort()){const sql=await fs.readFile('migrations/'+file,'utf8');for(const statement of sql.split(';').map(s=>s.trim()).filter(Boolean))await db.prepare(statement).run();}
 const hash=await bcrypt.hash('Test-password-only-2026!',12);
 for(const [id,email,role,change] of [['admin','admin@example.org','admin',0],['editor','editor@example.org','editor',0],['temporary','temporary@example.org','editor',1]])await db.prepare('INSERT INTO editors(id,email,display_name,role,password_hash,must_change_password,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)').bind(id,email,id,role,hash,change,'2026-10-10','2026-10-10').run();
 admin=await signIn('admin@example.org','Test-password-only-2026!');editor=await signIn('editor@example.org','Test-password-only-2026!');
});
after(async()=>{await mf?.dispose();});
test('unauthenticated access cannot read admin records or assets; public writes fail',async()=>{
 assert.equal((await call('/api/admin/stations')).status,401);
 const r=await call('/admin/app.js',{redirect:'manual'});assert.equal(r.status,302);assert.equal(r.headers.get('Location'),'/login');
 assert.equal((await request('/api/v1/stations','POST',{})).status,405);
 assert.equal((await call('/admin/index.html',{redirect:'manual'})).status,302);
});
test('station artwork is publicly readable',async()=>{
 const response=await call('/artwork/test-station.png');assert.equal(response.status,200);assert.equal(await response.text(),'test asset');
});
test('Wireless branding icon is publicly readable',async()=>{
 const response=await call('/wireless-app-icon.png');assert.equal(response.status,200);assert.equal(await response.text(),'test asset');
});
test('session cookies are protected and login requires same origin',async()=>{
 const r=await request('/api/auth/login','POST',{email:'admin@example.org',password:'Test-password-only-2026!'});const c=r.headers.get('Set-Cookie');assert.match(c,/HttpOnly/);assert.match(c,/Secure/);assert.match(c,/SameSite=Strict/);assert.match(c,/__Host-/);
 assert.equal((await request('/api/auth/login','POST',{email:'admin@example.org',password:'x'},null,{Origin:'https://evil.example'})).status,403);
 assert.equal((await request('/api/auth/login','POST',{email:'unknown@example.org',password:'invalid'})).status,401);
});
test('CSRF and editor role protect mutations and account management',async()=>{
 assert.equal((await request('/api/admin/stations','POST',sample(),admin,{'X-CSRF-Token':'wrong'})).status,403);
 assert.equal((await request('/api/admin/stations','POST',sample(),admin,{Origin:'https://evil.example'})).status,403);
 assert.equal((await call('/api/admin/users',{headers:{Cookie:editor.cookie}})).status,403);
 assert.equal((await request('/api/admin/users','POST',{email:'x@example.org',password:'Good-password-long!',display_name:'X',role:'admin'},editor)).status,403);
});
test('station create, API filtering, private data exclusion and ETag',async()=>{
 const r=await request('/api/admin/stations','POST',sample(),editor);assert.equal(r.status,201);const station=await r.json();assert.equal(station.version,1);
 const response=await call('/api/v1/stations?q=Test&city=Melbourne');assert.equal(response.status,200);const data=await response.json();assert.equal(data.total,1);assert.equal(data.stations[0].name,'Test Radio');assert.equal(data.stations[0].state,'Victoria');assert.equal(data.stations[0].frequency,'101.1 FM');assert.equal(data.stations[0].tagline,'Test radio tagline');assert.deepEqual(data.stations[0].genres,['Talkback','Sport']);assert.equal(data.stations[0].contact.sms,'0400 000 001');assert.equal(data.stations[0].contact.email,'studio@example.org');assert.ok(!('editorial_notes' in data.stations[0]));assert.ok(!('evidence' in data.stations[0].streams[0]));
 assert.equal((await call('/api/v1/stations?q=Test&city=Melbourne',{headers:{'If-None-Match':response.headers.get('ETag')}})).status,304);
 assert.equal((await call('/api/v1/stations?q=Test&city=Melbourne',{headers:{'If-None-Match':'"older", W/'+response.headers.get('ETag')}})).status,304);
 assert.equal((await call('/api/v1/stations?q=%25')).status,200);
 assert.equal((await call('/api/v1/stations?page_size=9999')).status,400);
 assert.equal((await call('/api/v1/stations?q=%27%20OR%201%3D1--').then(r=>r.json())).total,0);
});
test('new and changed streams are queued for technical testing',async()=>{
 const station=await call('/api/admin/stations?q=Test%20Radio',{headers:{Cookie:admin.cookie}}).then(r=>r.json()).then(data=>data.stations[0]);
 const row=await db.prepare("SELECT status,requested_url FROM stream_tests WHERE stream_id='stream_test'").first();assert.equal(row.status,'queued');assert.equal(row.requested_url,'https://example.org/audio.m3u8');
 const response=await request(`/api/admin/stations/${station.id}/streams/stream_test/test`,'POST',{},admin);assert.equal(response.status,202);assert.equal((await response.json()).status,'queued');
});
test('editors can upload cropped station artwork and it is publicly readable',async()=>{
 const {stations}=await call('/api/admin/stations?q=Test%20Radio',{headers:{Cookie:admin.cookie}}).then(r=>r.json());
 const webp=new Uint8Array([82,73,70,70,4,0,0,0,87,69,66,80,1,2,3,4]);
 const upload=await call(`/api/admin/stations/${stations[0].id}/artwork`,{method:'POST',headers:{Origin:origin,Cookie:admin.cookie,'X-CSRF-Token':admin.csrf,'X-Station-Version':String(stations[0].version),'Content-Type':'image/webp'},body:webp});
 assert.equal(upload.status,200);const data=await upload.json();assert.equal(data.width,1024);assert.equal(data.version,stations[0].version+1);assert.match(data.url,/\/station-artwork\/stations\//);
 const publicImage=await call(new URL(data.url).pathname);assert.equal(publicImage.status,200);assert.equal(publicImage.headers.get('Content-Type'),'image/webp');assert.deepEqual(new Uint8Array(await publicImage.arrayBuffer()),webp);
 const saved=await call('/api/admin/stations/'+stations[0].id,{headers:{Cookie:admin.cookie}}).then(r=>r.json());assert.equal(saved.logo_url,data.url);assert.equal(saved.version,data.version);
 assert.equal((await call(`/api/admin/stations/${stations[0].id}/artwork`,{method:'POST',headers:{Origin:origin,Cookie:admin.cookie,'X-CSRF-Token':admin.csrf,'X-Station-Version':String(stations[0].version),'Content-Type':'image/webp'},body:webp})).status,409);
 assert.equal((await call(`/api/admin/stations/${stations[0].id}/artwork`,{method:'POST',headers:{Origin:origin,Cookie:admin.cookie,'X-CSRF-Token':'wrong','Content-Type':'image/webp'},body:webp})).status,403);
});
test('drafts stay private and public endpoint never exposes disabled streams',async()=>{
 const value={...sample(),name:'Draft test',status:'draft',streams:[],preferred_stream_id:null};const r=await request('/api/admin/stations','POST',value,editor);const d=await r.json();assert.equal(r.status,201);
 assert.equal((await call('/api/v1/stations/'+d.id)).status,404);
 assert.equal((await call('/api/v1/stations?q=Draft').then(r=>r.json())).total,0);
 const bad=sample();bad.preferred_stream_id='not-owned';assert.equal((await request('/api/admin/stations','POST',bad,editor)).status,400);
});
test('stream changes clear verification and competing edits return conflict',async()=>{
 const {stations}=await call('/api/admin/stations?q=Test%20Radio',{headers:{Cookie:admin.cookie}}).then(r=>r.json());const s=stations[0];
 await db.prepare("UPDATE streams SET verification_status='audio_decoded',checked_at='2026-10-10',bitrate_kbps=128 WHERE id='stream_test'").run();
 const a=structuredClone(s),b=structuredClone(s);a.name='Winner A';b.name='Winner B';a.streams[0].url='https://example.org/changed-a.m3u8';b.streams[0].url='https://example.org/changed-b.m3u8';
 const results=await Promise.all([request('/api/admin/stations/'+s.id,'PUT',a,admin),request('/api/admin/stations/'+s.id,'PUT',b,editor)]);assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);
 const saved=await call('/api/admin/stations/'+s.id,{headers:{Cookie:admin.cookie}}).then(r=>r.json());assert.equal(saved.version,s.version+1);assert.equal(saved.streams[0].verification_status,'unverified');assert.equal(saved.streams[0].checked_at,null);assert.equal(saved.streams[0].bitrate_kbps,null);
 assert.equal((await request('/api/admin/stations/'+s.id,'PUT',s,admin)).status,409);
 const archived={...saved,status:'archived'};assert.equal((await request('/api/admin/stations/'+s.id,'PUT',archived,admin)).status,200);assert.equal((await call('/api/v1/stations/'+s.id)).status,404);
});
test('adding a stream preserves existing streams and their verification evidence',async()=>{
 const value={...sample(),name:'Stream editor test',status:'draft',streams:[{...sample().streams[0],id:'stream_editor_main',url:'https://example.org/stream-editor.m3u8'}],preferred_stream_id:'stream_editor_main'};const created=await request('/api/admin/stations','POST',value,admin);assert.equal(created.status,201);const station=await created.json();
 await db.prepare("UPDATE streams SET verification_status='audio_decoded',checked_at='2026-10-11',bitrate_kbps=128 WHERE id='stream_editor_main'").run();
 const current=await call('/api/admin/stations/'+station.id,{headers:{Cookie:admin.cookie}}).then(r=>r.json());current.streams.push({id:'stream_added',url:'https://example.org/alternative.mp3',label:'Alternative',format:'mp3',enabled:true,request_headers:{}});
 const savedResponse=await request('/api/admin/stations/'+station.id,'PUT',current,admin);assert.equal(savedResponse.status,200,await savedResponse.clone().text());const saved=await savedResponse.json();
 assert.equal(saved.streams.length,2);assert.equal(saved.streams.find(stream=>stream.id==='stream_editor_main').verification_status,'audio_decoded');assert.equal(saved.streams.find(stream=>stream.id==='stream_added').verification_status,'unverified');
});
test('state values are normalised and invalid states are rejected',async()=>{
 const value={...sample(),name:'State test',status:'draft',state:'NSW',streams:[{...sample().streams[0],id:'state_test_stream',url:'https://example.org/state.m3u8'}],preferred_stream_id:'state_test_stream'};const response=await request('/api/admin/stations','POST',value,admin);assert.equal(response.status,201);assert.equal((await response.json()).state,'New South Wales');
 value.name='National service';value.state='national';value.streams[0].id='national_state_stream';value.preferred_stream_id='national_state_stream';const national=await request('/api/admin/stations','POST',value,admin);assert.equal(national.status,201);assert.equal((await national.json()).state,'National');
 value.name='Bad state';value.state='Atlantis';assert.equal((await request('/api/admin/stations','POST',value,admin)).status,400);
});
test('one shared artwork asset can be assigned to multiple stations',async()=>{
 const firstValue={...sample(),name:'Shared art one',status:'draft',streams:[{...sample().streams[0],id:'shared_one_stream',url:'https://example.org/shared-one.m3u8'}],preferred_stream_id:'shared_one_stream'};const first=await request('/api/admin/stations','POST',firstValue,admin).then(r=>r.json());
 const secondValue={...sample(),name:'Shared art two',status:'draft',streams:[{...sample().streams[0],id:'shared_two_stream',url:'https://example.org/shared-two.m3u8'}],preferred_stream_id:'shared_two_stream'};const second=await request('/api/admin/stations','POST',secondValue,admin).then(r=>r.json());
 const webp=new Uint8Array([82,73,70,70,4,0,0,0,87,69,66,80,1,2,3,4]);const upload=await call('/api/admin/artwork',{method:'POST',headers:{Origin:origin,Cookie:admin.cookie,'X-CSRF-Token':admin.csrf,'Content-Type':'image/webp'},body:webp});assert.equal(upload.status,201);const asset=await upload.json();
 const assigned=await request(`/api/admin/artwork/${asset.id}/assign`,'POST',{station_ids:[first.id,second.id],versions:{[first.id]:first.version,[second.id]:second.version}},admin);assert.equal(assigned.status,200,await assigned.clone().text());const result=await assigned.json();assert.equal(result.stations.length,2);
 for(const id of [first.id,second.id])assert.equal((await call('/api/admin/stations/'+id,{headers:{Cookie:admin.cookie}}).then(r=>r.json())).logo_url,asset.url);
});
test('duplicate merge combines streams and metadata while preserving complete source records',async()=>{
 const targetValue={...sample(),name:'Merge FM',status:'draft',genres:['Talkback'],aliases:['Merge Radio'],streams:[{...sample().streams[0],id:'merge_target',url:'https://example.org/merge-shared.m3u8'}],preferred_stream_id:'merge_target'};const target=await request('/api/admin/stations','POST',targetValue,admin).then(r=>r.json());
 const sourceValue={...sample(),name:'Merge FM Regional',status:'draft',state:'NSW',cities:['Newcastle'],genres:['Sport'],description:'Regional description',contact:{...sample().contact,sms:'0499 999 999'},streams:[{...sample().streams[0],id:'merge_duplicate',url:'https://example.org/merge-shared.m3u8'},{...sample().streams[0],id:'merge_unique',url:'https://example.org/merge.mp3',format:'mp3'}],preferred_stream_id:'merge_unique'};const source=await request('/api/admin/stations','POST',sourceValue,admin).then(r=>r.json());
 const response=await request('/api/admin/stations/merge','POST',{target_id:target.id,source_ids:[source.id],versions:{[target.id]:target.version,[source.id]:source.version}},admin);assert.equal(response.status,200,await response.clone().text());const merged=await response.json();
 assert.deepEqual(new Set(merged.genres),new Set(['Talkback','Sport']));assert.ok(merged.cities.includes('Newcastle'));assert.ok(merged.aliases.includes('Merge FM Regional'));assert.equal(merged.streams.length,2);assert.equal(merged.merge_archive.length,1);assert.equal(merged.merge_archive[0].source.name,'Merge FM Regional');assert.equal((await call('/api/admin/stations/'+source.id,{headers:{Cookie:admin.cookie}})).status,404);
});
test('temporary password blocks editing until changed and revokes the old session',async()=>{
 const session=await signIn('temporary@example.org','Test-password-only-2026!');assert.equal(session.user.must_change_password,true);
 assert.equal((await call('/api/admin/stations',{headers:{Cookie:session.cookie}})).status,428);
 const result=await request('/api/auth/password','POST',{current_password:'Test-password-only-2026!',new_password:'Replacement-password-2026!'},session);assert.equal(result.status,200);assert.equal((await result.json()).user.must_change_password,false);
 assert.equal((await call('/api/admin/me',{headers:{Cookie:session.cookie}})).status,401);
});
test('disabled editors immediately lose access and admins cannot disable themselves',async()=>{
 assert.equal((await request('/api/admin/users/admin','PATCH',{disabled:true},admin)).status,400);
 assert.equal((await request('/api/admin/users/editor','PATCH',{disabled:true},admin)).status,200);
 assert.equal((await call('/api/admin/me',{headers:{Cookie:editor.cookie}})).status,401);
});
test('validation rejects unsafe schemes, private URLs, foreign credentials and fake verification',async()=>{
 for(const url of ['javascript:alert(1)','http://127.0.0.1/stream','http://10.0.0.2/a','https://user:pass@example.org/a']){const s=sample();s.streams[0].url=url;assert.equal((await request('/api/admin/stations','POST',s,admin)).status,400);}
 const s={...sample(),name:'New evidence',streams:[{...sample().streams[0],id:'new_evidence',verification_status:'audio_decoded',bitrate_kbps:999}]};s.preferred_stream_id='new_evidence';const result=await request('/api/admin/stations','POST',s,admin);assert.equal(result.status,201);assert.equal((await result.json()).streams[0].verification_status,'unverified');
});
test('login throttles repeated attempts without storing plaintext passwords',async()=>{
 const key=await import('../src/auth.js').then(m=>m.sha256('throttle@example.org'));
 await db.prepare('INSERT INTO login_limits VALUES(?,?,?)').bind('email:'+key,10,Math.floor(Date.now()/1000)+900).run();
 const r=await request('/api/auth/login','POST',{email:'throttle@example.org',password:'invalid'});assert.equal(r.status,429);assert.equal(r.headers.get('Retry-After'),'900');
 const events=(await db.prepare('SELECT details_json FROM audit_log').all()).results;assert.ok(events.every(e=>!e.details_json.includes('password-only')&&!e.details_json.includes('Replacement-password')));
});
