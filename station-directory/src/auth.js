import bcrypt from 'bcryptjs';
import {bodyJSON,fail,json,nowISO,sameOrigin,text} from './http.js';

const COOKIE='__Host-srd_session';
const SESSION_SECONDS=8*60*60;
const COST=12;
// Valid cost-matched dummy hash prevents a cheap account-existence timing shortcut.
const DUMMY_HASH='$2b$12$R9h/cIPz0gi.URNNX3kh2OPST9/PgBkqquzi.Ss7KIUgO2t0jWMUW';
export const randomToken=()=>Array.from(crypto.getRandomValues(new Uint8Array(32)),b=>b.toString(16).padStart(2,'0')).join('');
export async function sha256(value){return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value))),b=>b.toString(16).padStart(2,'0')).join('');}
export function validPassword(password){if(typeof password!=='string'||password.length<14||new TextEncoder().encode(password).length>72)fail(400,'Use a password of at least 14 characters and at most 72 UTF-8 bytes.');return password;}
export function validEmail(value){const email=text(value,'Email',254,true).toLowerCase();if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))fail(400,'Enter a valid email address.');return email;}
export async function hashPassword(password){return bcrypt.hash(password,COST);}
function cookie(token,age=SESSION_SECONDS){return `${COOKIE}=${token}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${age}`;}
function readCookie(request){const matches=(request.headers.get('Cookie')||'').split(';').map(s=>s.trim()).filter(s=>s.startsWith(COOKIE+'='));return matches.length===1?matches[0].slice(COOKIE.length+1):null;}
export function publicEditor(editor){return {id:editor.id,email:editor.email,display_name:editor.display_name,role:editor.role,must_change_password:!!editor.must_change_password};}
async function rateLimit(db,request,email){
  const now=Math.floor(Date.now()/1000),window=15*60;
  const keys=[['ip:'+await sha256(request.headers.get('CF-Connecting-IP')||'local-development'),30],['email:'+await sha256(email),10]];
  const result=await db.batch(keys.map(([key])=>db.prepare('INSERT INTO login_limits(key,attempts,resets_at) VALUES(?,1,?) ON CONFLICT(key) DO UPDATE SET attempts=CASE WHEN resets_at<=? THEN 1 ELSE attempts+1 END,resets_at=CASE WHEN resets_at<=? THEN ? ELSE resets_at END RETURNING attempts,resets_at').bind(key,now+window,now,now,now+window)));
  if(result.some((r,i)=>r.results[0].attempts>keys[i][1]))fail(429,'Too many sign-in attempts. Please try again in 15 minutes.',{'Retry-After':'900'});
}
async function newSession(db,editor){
  const token=randomToken(),csrf=randomToken(),now=Math.floor(Date.now()/1000);
  await db.batch([db.prepare('DELETE FROM sessions WHERE expires_at<=?').bind(now),db.prepare('DELETE FROM login_limits WHERE resets_at<=?').bind(now),db.prepare('INSERT INTO sessions VALUES(?,?,?,?,?)').bind(await sha256(token),editor.id,csrf,now+SESSION_SECONDS,now)]);
  return json({user:publicEditor(editor),csrf_token:csrf},200,{'Set-Cookie':cookie(token)});
}
export async function login(request,db){
  sameOrigin(request);const input=await bodyJSON(request,4096),email=validEmail(input.email);
  const password=typeof input.password==='string'?input.password:'';if(new TextEncoder().encode(password).length>72)fail(401,'Email or password is incorrect.');
  await rateLimit(db,request,email);
  const editor=await db.prepare('SELECT * FROM editors WHERE email=?').bind(email).first();
  const correct=await bcrypt.compare(password,editor?.password_hash||DUMMY_HASH);
  if(!correct||!editor||editor.disabled)fail(401,'Email or password is incorrect.');
  return newSession(db,editor);
}
export async function authenticate(request,db){
  const token=readCookie(request);if(!token||!/^[a-f0-9]{64}$/.test(token))fail(401,'Please sign in.');
  const user=await db.prepare('SELECT e.*,s.csrf_token,s.token_hash FROM sessions s JOIN editors e ON e.id=s.editor_id WHERE s.token_hash=? AND s.expires_at>? AND e.disabled=0').bind(await sha256(token),Math.floor(Date.now()/1000)).first();
  if(!user)fail(401,'Your session has expired. Please sign in again.');return user;
}
export function requireWrite(request,editor){sameOrigin(request);if(request.headers.get('X-CSRF-Token')!==editor.csrf_token)fail(403,'The security token has expired. Reload the page.');}
export function requireAdmin(editor){if(editor.role!=='admin')fail(403,'Administrator access is required.');}
export async function logout(request,db,editor){requireWrite(request,editor);await db.prepare('DELETE FROM sessions WHERE token_hash=?').bind(editor.token_hash).run();return json({ok:true},200,{'Set-Cookie':cookie('',0)});}
export async function changePassword(request,db,editor){
  requireWrite(request,editor);const input=await bodyJSON(request,4096),password=validPassword(input.new_password);
  if(typeof input.current_password!=='string'||new TextEncoder().encode(input.current_password).length>72||!await bcrypt.compare(input.current_password,editor.password_hash))fail(400,'The current password is incorrect.');
  if(await bcrypt.compare(password,editor.password_hash))fail(400,'Choose a different password.');
  const hash=await hashPassword(password),stamp=nowISO();
  await db.batch([db.prepare('UPDATE editors SET password_hash=?,must_change_password=0,updated_at=? WHERE id=?').bind(hash,stamp,editor.id),db.prepare('DELETE FROM sessions WHERE editor_id=?').bind(editor.id),db.prepare('INSERT INTO audit_log VALUES(?,?,?,?,NULL,?,?)').bind(crypto.randomUUID(),editor.id,editor.email,'account.password_changed','{}',stamp)]);
  return newSession(db,{...editor,must_change_password:0});
}
export async function listEditors(db,editor){requireAdmin(editor);return json({users:(await db.prepare('SELECT id,email,display_name,role,disabled,must_change_password,created_at FROM editors ORDER BY email').all()).results});}
export async function createEditor(request,db,actor){
  requireAdmin(actor);const input=await bodyJSON(request,4096),email=validEmail(input.email),displayName=text(input.display_name,'Name',100,true),password=validPassword(input.password),role=input.role;
  if(!['admin','editor'].includes(role))fail(400,'Choose administrator or editor.');
  const id=crypto.randomUUID(),stamp=nowISO(),hash=await hashPassword(password);
  try{await db.batch([db.prepare('INSERT INTO editors(id,email,display_name,role,password_hash,must_change_password,created_at,updated_at) VALUES(?,?,?,?,?,1,?,?)').bind(id,email,displayName,role,hash,stamp,stamp),db.prepare('INSERT INTO audit_log VALUES(?,?,?,?,NULL,?,?)').bind(crypto.randomUUID(),actor.id,actor.email,'account.created',JSON.stringify({email,role}),stamp)]);}catch(error){if(String(error).includes('UNIQUE'))fail(409,'An account with that email already exists.');throw error;}
  return json({id,email,display_name:displayName,role,must_change_password:true},201);
}
export async function updateEditor(request,db,actor,id){
  requireAdmin(actor);if(id===actor.id)fail(400,'Use Change password for your own account. You cannot disable yourself.');
  const input=await bodyJSON(request,4096),user=await db.prepare('SELECT * FROM editors WHERE id=?').bind(id).first();if(!user)fail(404,'Account not found.');
  if(typeof input.disabled!=='boolean')fail(400,'Account status is required.');
  const hash=input.password?await hashPassword(validPassword(input.password)):null,stamp=nowISO();
  const result=await db.batch([
    db.prepare("UPDATE editors SET disabled=?,password_hash=COALESCE(?,password_hash),must_change_password=CASE WHEN ? IS NULL THEN must_change_password ELSE 1 END,updated_at=? WHERE id=? AND (role!='admin' OR ?=0 OR (SELECT COUNT(*) FROM editors WHERE role='admin' AND disabled=0 AND id!=?)>0)").bind(input.disabled?1:0,hash,hash,stamp,id,input.disabled?1:0,id),
    db.prepare('DELETE FROM sessions WHERE editor_id=?').bind(id),
    db.prepare('INSERT INTO audit_log VALUES(?,?,?,?,NULL,?,?)').bind(crypto.randomUUID(),actor.id,actor.email,'account.updated',JSON.stringify({email:user.email,disabled:input.disabled,password_reset:!!hash}),stamp)
  ]);
  if(!result[0].meta.changes)fail(409,'At least one active administrator is required.');return json({ok:true});
}
