import {HTTPError,fail,json,secured} from './http.js';
import {login,authenticate,requireWrite,logout,changePassword,publicEditor,listEditors,createEditor,updateEditor,sha256} from './auth.js';
import {listStations,getStation,saveStation,mergeStations,filters} from './catalogue.js';
import {serveArtwork,uploadArtwork,uploadSharedArtwork,assignSharedArtwork} from './artwork.js';
import {listNetworkArtwork,uploadNetworkArtwork} from './network-artwork.js';
import {requestStreamTest,processPendingStreamTests} from './stream-testing.js';

async function publicResponse(request,data){
  const etag='"'+(await sha256(JSON.stringify(data)))+'"';
  const headers={'Cache-Control':'public, max-age=0, must-revalidate','ETag':etag,'Access-Control-Allow-Origin':'*','Access-Control-Expose-Headers':'ETag'};
  const matches=(request.headers.get('If-None-Match')||'').split(',').some(value=>value.trim()==='*'||value.trim().replace(/^W\//,'')===etag);
  if(matches)return new Response(null,{status:304,headers});return json(data,200,headers);
}
async function asset(request,env,path){const url=new URL(request.url);if(path)url.pathname=path;const response=await env.ASSETS.fetch(new Request(url,request));const headers=new Headers(response.headers);headers.set('Cache-Control','no-store');return new Response(response.body,{status:response.status,headers});}
async function route(request,env,ctx){
  const url=new URL(request.url),path=url.pathname;
  if(path==='/health'&&request.method==='GET')return json({service:'wireless-directory',schema_version:1,status:'ok'});
  if(path.startsWith('/artwork/')&&request.method==='GET')return asset(request,env);
  if(path.startsWith('/station-artwork/')&&request.method==='GET')return serveArtwork(request,env.ARTWORK,path.slice('/station-artwork/'.length));
  if(path.startsWith('/api/v1/')){
    if(request.method==='OPTIONS')return new Response(null,{status:204,headers:{'Access-Control-Allow-Origin':'*','Access-Control-Allow-Methods':'GET, OPTIONS','Access-Control-Allow-Headers':'If-None-Match','Access-Control-Max-Age':'86400'}});
    if(request.method!=='GET')fail(405,'This catalogue API is read-only.',{'Allow':'GET, OPTIONS'});
    if(path==='/api/v1/stations')return publicResponse(request,await listStations(env.DB,url));
    if(path==='/api/v1/filters')return publicResponse(request,await filters(env.DB));
    if(path==='/api/v1/networks')return publicResponse(request,await listNetworkArtwork(env.DB));
    if(path==='/api/v1/catalogue')return publicResponse(request,{schema_version:1,...await env.DB.prepare('SELECT revision,updated_at FROM catalogue_meta WHERE id=1').first()});
    const match=path.match(/^\/api\/v1\/stations\/([\w-]+)$/);if(match)return publicResponse(request,await getStation(env.DB,match[1]));
    fail(404,'Endpoint not found.');
  }
  if(path==='/api/auth/login'&&request.method==='POST')return login(request,env.DB);
  if((path==='/login'||path==='/login/')&&request.method==='GET')return asset(request,env,'/login.html');
  if(['/login.js','/styles.css','/wireless-app-icon.png'].includes(path)&&request.method==='GET')return asset(request,env);
  if(path==='/'&&request.method==='GET')return Response.redirect(url.origin+'/admin/',302);
  if(path.startsWith('/admin')||path.startsWith('/api/admin/')||path.startsWith('/api/auth/')){
    let editor;
    try{editor=await authenticate(request,env.DB);}catch(error){if(error.status===401&&!path.startsWith('/api/'))return new Response(null,{status:302,headers:{Location:'/login','Cache-Control':'no-store'}});throw error;}
    if(path==='/api/auth/logout'&&request.method==='POST')return logout(request,env.DB,editor);
    if(path==='/api/auth/password'&&request.method==='POST')return changePassword(request,env.DB,editor);
    if(path==='/api/admin/me'&&request.method==='GET')return json({user:publicEditor(editor),csrf_token:editor.csrf_token});
    if(path.startsWith('/api/')&&editor.must_change_password)fail(428,'Change your temporary password before editing the catalogue.');
    if(path.startsWith('/api/')&&!['GET','HEAD','OPTIONS'].includes(request.method))requireWrite(request,editor);
    if(path==='/api/admin/stations'&&request.method==='GET')return json(await listStations(env.DB,url,true));
    if(path==='/api/admin/stations'&&request.method==='POST'){const response=await saveStation(request,env.DB,editor,null);ctx.waitUntil(processPendingStreamTests(env));return response;}
    if(path==='/api/admin/stations/merge'&&request.method==='POST')return mergeStations(request,env.DB,editor);
    if(path==='/api/admin/artwork'&&request.method==='POST')return uploadSharedArtwork(request,env,editor);
    if(path==='/api/admin/filters'&&request.method==='GET')return json(await filters(env.DB,true));
    if(path==='/api/admin/networks'&&request.method==='GET')return json(await listNetworkArtwork(env.DB,true));
    if(path==='/api/admin/users'&&request.method==='GET')return listEditors(env.DB,editor);
    if(path==='/api/admin/users'&&request.method==='POST')return createEditor(request,env.DB,editor);
    if(path==='/api/admin/audit'&&request.method==='GET')return json({events:(await env.DB.prepare('SELECT * FROM audit_log ORDER BY created_at DESC,id DESC LIMIT 100').all()).results});
    let match=path.match(/^\/api\/admin\/stations\/([\w-]+)$/);
    if(match&&request.method==='GET')return json(await getStation(env.DB,match[1],true));
    if(match&&request.method==='PUT'){const response=await saveStation(request,env.DB,editor,match[1]);ctx.waitUntil(processPendingStreamTests(env));return response;}
    match=path.match(/^\/api\/admin\/stations\/([\w-]+)\/streams\/([\w-]+)\/test$/);
    if(match&&request.method==='POST'){const response=await requestStreamTest(request,env.DB,editor,match[1],match[2]);ctx.waitUntil(processPendingStreamTests(env,1));return response;}
    match=path.match(/^\/api\/admin\/stations\/([\w-]+)\/artwork$/);
    if(match&&request.method==='POST')return uploadArtwork(request,env,editor,match[1]);
    match=path.match(/^\/api\/admin\/networks\/(.+)\/artwork$/);
    if(match&&request.method==='POST')return uploadNetworkArtwork(request,env,editor,match[1]);
    match=path.match(/^\/api\/admin\/artwork\/([\w-]+)\/assign$/);
    if(match&&request.method==='POST')return assignSharedArtwork(request,env,editor,match[1]);
    match=path.match(/^\/api\/admin\/users\/([\w-]+)$/);if(match&&request.method==='PATCH')return updateEditor(request,env.DB,editor,match[1]);
    if(request.method==='GET'&&(path==='/admin'||path==='/admin/'))return asset(request,env,'/admin/index.html');
    if(request.method==='GET'&&path==='/admin/app.js')return asset(request,env);
    fail(404,'Page or endpoint not found.');
  }
  fail(404,'Page not found.');
}
export default {
 async fetch(request,env,ctx){try{return secured(await route(request,env,ctx));}catch(error){if(error instanceof HTTPError)return secured(json({error:error.message},error.status,error.headers));console.error('Request failed',error?.stack||error?.name||'Error');return secured(json({error:'The service could not complete this request. Please try again.'},500));}},
 async scheduled(_event,env,ctx){ctx.waitUntil(processPendingStreamTests(env,4));}
};
