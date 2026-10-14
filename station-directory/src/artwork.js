import {fail,json,nowISO,bodyJSON,text} from './http.js';

const MAX_BYTES=3*1024*1024;

function detectedType(bytes){
  if(bytes.length>=12&&String.fromCharCode(...bytes.slice(0,4))==='RIFF'&&String.fromCharCode(...bytes.slice(8,12))==='WEBP')return 'image/webp';
  if(bytes.length>=8&&[137,80,78,71,13,10,26,10].every((value,index)=>bytes[index]===value))return 'image/png';
  if(bytes.length>=3&&bytes[0]===255&&bytes[1]===216&&bytes[2]===255)return 'image/jpeg';
  return null;
}

async function imagePayload(request){
  const declared=Number(request.headers.get('Content-Length')||0);
  if(declared>MAX_BYTES)fail(413,'The cropped artwork must be no larger than 3 MB.');
  const bytes=new Uint8Array(await request.arrayBuffer());
  if(!bytes.length)fail(400,'Choose an image to upload.');
  if(bytes.length>MAX_BYTES)fail(413,'The cropped artwork must be no larger than 3 MB.');
  const contentType=detectedType(bytes);
  if(!contentType)fail(415,'Upload a cropped PNG, JPEG or WebP image.');
  return {bytes,contentType,extension:{'image/webp':'webp','image/png':'png','image/jpeg':'jpg'}[contentType]};
}

export async function uploadArtwork(request,env,editor,stationID){
  if(!env.ARTWORK)fail(503,'Artwork storage is not configured.');
  const station=await env.DB.prepare('SELECT id,version,logo_url FROM stations WHERE id=?').bind(stationID).first();
  if(!station)fail(404,'Save the station before uploading its artwork.');
  const expectedVersion=Number(request.headers.get('X-Station-Version'));
  if(!Number.isInteger(expectedVersion)||expectedVersion!==station.version)fail(409,'Another editor has changed this station. Reload it before uploading artwork.');
  const {bytes,contentType,extension}=await imagePayload(request);
  const key=`stations/${stationID}/${crypto.randomUUID()}.${extension}`;
  await env.ARTWORK.put(key,bytes,{httpMetadata:{contentType,cacheControl:'public, max-age=31536000, immutable'},customMetadata:{station_id:stationID,uploaded_by:editor.id}});
  const stamp=nowISO(),url=new URL('/station-artwork/'+key,request.url).href,version=station.version+1;
  const results=await env.DB.batch([
    env.DB.prepare('UPDATE stations SET logo_url=?,version=?,updated_at=?,updated_by=? WHERE id=? AND version=?').bind(url,version,stamp,editor.email,stationID,station.version),
    env.DB.prepare('UPDATE catalogue_meta SET revision=revision+1,updated_at=? WHERE id=1').bind(stamp),
    env.DB.prepare('INSERT INTO audit_log VALUES(?,?,?,?,?,?,?)').bind(crypto.randomUUID(),editor.id,editor.email,'station.artwork_updated',stationID,JSON.stringify({before:station.logo_url,after:url,key,content_type:contentType,bytes:bytes.length,version}),stamp)
  ]);
  if(!results[0].meta.changes)fail(409,'Another editor has changed this station. Reload it before uploading artwork.');
  return json({url,width:1024,height:1024,content_type:contentType,version},200);
}

export async function uploadSharedArtwork(request,env,editor){
  if(!env.ARTWORK)fail(503,'Artwork storage is not configured.');
  const {bytes,contentType,extension}=await imagePayload(request),id=crypto.randomUUID(),key=`shared/${id}.${extension}`,stamp=nowISO(),url=new URL('/station-artwork/'+key,request.url).href;
  await env.ARTWORK.put(key,bytes,{httpMetadata:{contentType,cacheControl:'public, max-age=31536000, immutable'},customMetadata:{asset_id:id,uploaded_by:editor.id}});
  try{await env.DB.prepare('INSERT INTO artwork_assets(id,object_key,url,content_type,byte_count,created_at,created_by) VALUES(?,?,?,?,?,?,?)').bind(id,key,url,contentType,bytes.length,stamp,editor.email).run();}
  catch(error){await env.ARTWORK.delete(key);throw error;}
  return json({id,url,width:1024,height:1024,content_type:contentType},201);
}

export async function assignSharedArtwork(request,env,editor,assetID){
  const asset=await env.DB.prepare('SELECT * FROM artwork_assets WHERE id=?').bind(assetID).first();
  if(!asset)fail(404,'Shared artwork was not found. Upload it again.');
  const input=await bodyJSON(request),stationIDs=Array.isArray(input.station_ids)?[...new Set(input.station_ids.map(value=>text(value,'Station ID',120,true)))]:[],versions=input.versions??{};
  if(!stationIDs.length||stationIDs.length>100)fail(400,'Choose between one and 100 stations for this artwork.');
  const rows=(await env.DB.prepare(`SELECT id,name,version,logo_url FROM stations WHERE id IN (${stationIDs.map(()=>'?').join(',')})`).bind(...stationIDs).all()).results;
  if(rows.length!==stationIDs.length)fail(404,'One or more selected stations no longer exist. Reload the results.');
  for(const row of rows)if(!Number.isInteger(versions[row.id])||versions[row.id]!==row.version)fail(409,'A selected station has changed. Reload the results before assigning artwork.');
  const stamp=nowISO(),mutation=crypto.randomUUID(),statements=[];
  for(const row of rows){
    statements.push(env.DB.prepare('INSERT INTO mutation_locks (station_id,expected_version,mutation_id,guard) VALUES(?,?,?,CASE WHEN EXISTS(SELECT 1 FROM stations WHERE id=? AND version=?) THEN 1 ELSE 0 END)').bind(row.id,row.version,`${mutation}-${row.id}`,row.id,row.version));
    statements.push(env.DB.prepare('UPDATE stations SET logo_url=?,version=version+1,updated_at=?,updated_by=? WHERE id=? AND version=?').bind(asset.url,stamp,editor.email,row.id,row.version));
    statements.push(env.DB.prepare('INSERT INTO audit_log VALUES(?,?,?,?,?,?,?)').bind(crypto.randomUUID(),editor.id,editor.email,'station.shared_artwork_assigned',row.id,JSON.stringify({before:row.logo_url,after:asset.url,asset_id:asset.id}),stamp));
  }
  statements.push(env.DB.prepare('UPDATE catalogue_meta SET revision=revision+1,updated_at=? WHERE id=1').bind(stamp));
  try{await env.DB.batch(statements);}catch(error){const message=String(error);if(message.includes('mutation_locks')||message.includes('guard'))fail(409,'A selected station changed during artwork assignment. Reload the results and try again.');throw error;}
  return json({asset_id:asset.id,url:asset.url,stations:rows.map(row=>({id:row.id,name:row.name,version:row.version+1}))},200);
}

export async function serveArtwork(request,bucket,key){
  if(!bucket)fail(404,'Artwork not found.');
  const object=await bucket.get(key);
  if(!object)fail(404,'Artwork not found.');
  const headers=new Headers({'Content-Type':object.httpMetadata?.contentType||'application/octet-stream','Cache-Control':object.httpMetadata?.cacheControl||'public, max-age=31536000, immutable'});headers.set('ETag',object.httpEtag);headers.set('Access-Control-Allow-Origin','*');headers.set('X-Content-Type-Options','nosniff');
  if(request.headers.get('If-None-Match')===object.httpEtag)return new Response(null,{status:304,headers});
  return new Response(object.body,{headers});
}
