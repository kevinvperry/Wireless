// Operator-only provisioning. Read JSON from stdin; never put passwords in command-line arguments.
import {readFileSync,writeFileSync,unlinkSync,mkdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import bcrypt from 'bcryptjs';
const remote=process.argv.includes('--remote');
const input=JSON.parse(readFileSync(0,'utf8'));
if(!input.email||!input.display_name||!input.password)throw new Error('Email, display_name and password are required on stdin.');
if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.email))throw new Error('Invalid email.');
if(new TextEncoder().encode(input.password).length>72)throw new Error('Password exceeds bcrypt input limit.');
const role=input.role||'admin';if(!['admin','editor'].includes(role))throw new Error('Invalid role.');
const hash=await bcrypt.hash(input.password,12);delete input.password;
const q=s=>"'"+String(s).replaceAll("'","''")+"'";
const stamp=new Date().toISOString(),id=randomUUID(),temporary=remote||input.must_change_password!==false;
const sql=`INSERT OR IGNORE INTO editors(id,email,display_name,role,password_hash,must_change_password,created_at,updated_at) VALUES(${[id,input.email.toLowerCase(),input.display_name,role,hash].map(q).join(',')},${temporary?1:0},${q(stamp)},${q(stamp)});`;
mkdirSync('.wrangler',{recursive:true});const file='.wrangler/provision-'+id+'.sql';
try{writeFileSync(file,sql,{mode:0o600});execFileSync('./node_modules/.bin/wrangler',['d1','execute','DB',remote?'--remote':'--local','--file',file,'--json'],{stdio:['ignore','pipe','pipe']});console.log(`Provisioned ${input.email} (${role}); existing accounts are not overwritten.`);}finally{unlinkSync(file);}
