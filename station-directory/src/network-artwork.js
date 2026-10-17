import {fail,json,nowISO,text} from './http.js';
import {imagePayload} from './artwork.js';

export async function listNetworkArtwork(db,admin=false){
  const rows=(await db.prepare(`SELECT n.network,COALESCE(a.image_url,'') image_url,COALESCE(a.version,0) version,COALESCE(a.updated_at,'') updated_at${admin?",COALESCE(a.updated_by,'') updated_by":''} FROM (SELECT DISTINCT network FROM stations WHERE network<>''${admin?'':" AND status='published'"}) n LEFT JOIN network_artwork a ON a.network=n.network ORDER BY n.network COLLATE NOCASE`).all()).results;
  const meta=await db.prepare('SELECT revision FROM catalogue_meta WHERE id=1').first();
  return {schema_version:1,revision:meta.revision,networks:rows};
}

export async function uploadNetworkArtwork(request,env,editor,networkName){
  if(!env.ARTWORK)fail(503,'Artwork storage is not configured.');
  const network=text(decodeURIComponent(networkName),'Network',100,true);
  const exists=await env.DB.prepare('SELECT 1 FROM stations WHERE network=? LIMIT 1').bind(network).first();
  if(!exists)fail(404,'That network is not present in the directory.');
  const current=await env.DB.prepare('SELECT * FROM network_artwork WHERE network=?').bind(network).first();
  const expectedVersion=Number(request.headers.get('X-Network-Version'));
  if(!Number.isInteger(expectedVersion)||expectedVersion!==(current?.version??0))fail(409,'Another editor has changed this network image. Reload it before uploading artwork.');
  const {bytes,contentType,extension}=await imagePayload(request);
  const key=`networks/${crypto.randomUUID()}.${extension}`;
  await env.ARTWORK.put(key,bytes,{httpMetadata:{contentType,cacheControl:'public, max-age=31536000, immutable'},customMetadata:{network,uploaded_by:editor.id}});
  const stamp=nowISO(),url=new URL('/station-artwork/'+key,request.url).href,version=(current?.version??0)+1;
  await env.DB.batch([
    env.DB.prepare('INSERT INTO network_artwork(network,image_url,version,updated_at,updated_by) VALUES(?,?,?,?,?) ON CONFLICT(network) DO UPDATE SET image_url=excluded.image_url,version=excluded.version,updated_at=excluded.updated_at,updated_by=excluded.updated_by').bind(network,url,version,stamp,editor.email),
    env.DB.prepare('UPDATE catalogue_meta SET revision=revision+1,updated_at=? WHERE id=1').bind(stamp),
    env.DB.prepare('INSERT INTO audit_log VALUES(?,?,?,?,?,?,?)').bind(crypto.randomUUID(),editor.id,editor.email,'network.artwork_updated',network,JSON.stringify({before:current?.image_url??'',after:url,key,content_type:contentType,bytes:bytes.length,version}),stamp)
  ]);
  return json({network,image_url:url,width:1024,height:1024,content_type:contentType,version},200);
}
