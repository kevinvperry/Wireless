import {fail,json,text,publicURL,nowISO,bodyJSON} from './http.js';
import {queueTests} from './stream-testing.js';

const statuses=['draft','published','archived'];
export const australianStates=['Unknown','National','Australian Capital Territory','New South Wales','Northern Territory','Queensland','South Australia','Tasmania','Victoria','Western Australia'];
const stateAliases={ACT:'Australian Capital Territory',NSW:'New South Wales',NT:'Northern Territory',QLD:'Queensland',SA:'South Australia',TAS:'Tasmania',VIC:'Victoria',WA:'Western Australia'};
function australianState(value){const raw=text(value??'','State',60).trim();if(!raw)return 'Unknown';const normalized=stateAliases[raw.toUpperCase()]??australianStates.find(v=>v.toLowerCase()===raw.toLowerCase());if(!normalized)fail(400,'Choose National, an Australian state or territory, or Unknown.');return normalized;}
function uniqueText(values){const seen=new Set();return values.flat().map(value=>String(value??'').trim()).filter(value=>{if(!value)return false;const key=value.toLocaleLowerCase('en-AU');return !seen.has(key)&&seen.add(key);});}
function parseJSON(value,fallback){try{return JSON.parse(value??'');}catch{return fallback;}}
export function validateStation(value) {
  const station={name:text(value.name,'Station name',160,true),network:text(value.network??'','Network',100),country:text(value.country??'AU','Country',2,true).toUpperCase(),state:australianState(value.state),frequency:text(value.frequency??'','Frequency',100),tagline:text(value.tagline??'','Tagline',300),description:text(value.description??'','Description',3000),website_url:publicURL(value.website_url??'','Website',{optional:true}),logo_url:publicURL(value.logo_url??'','Logo',{optional:true,httpsOnly:true}),editorial_notes:text(value.editorial_notes??'','Editorial notes',8000)};
  if(!/^[A-Z]{2}$/.test(station.country))fail(400,'Use a two-letter country code.');
  for(const key of ['cities','tags','genres']){const entries=value[key]??[];if(!Array.isArray(entries)||entries.length>30)fail(400,`${key} must contain at most 30 entries.`);station[key]=[...new Set(entries.map(v=>text(v,key,80,true)))];}
  const contact=value.contact??{};if(!contact||typeof contact!=='object'||Array.isArray(contact))fail(400,'Contact information must be an object.');station.contact={};
  for(const key of ['talkback_phone','sms','office_phone','email','address','contact_page']){const entry=contact[key];station.contact[key]=entry===null||entry===undefined?'':text(entry,`Contact ${key}`,key==='address'?500:254);}
  if(station.contact.email&&!/^\S+@\S+\.\S+$/.test(station.contact.email))fail(400,'Enter a valid contact email address.');
  station.contact.contact_page=publicURL(station.contact.contact_page,'Contact page',{optional:true});
  if(!statuses.includes(value.status))fail(400,'Choose draft, published or archived.');station.status=value.status;
  if(!Array.isArray(value.streams)||value.streams.length>40)fail(400,'A station may have at most 40 stream URLs.');
  const ids=new Set(),urls=new Set();station.streams=value.streams.map(stream=>{
    const id=stream.id?text(stream.id,'Stream ID',120,true):crypto.randomUUID();if(!/^[\w-]+$/.test(id)||ids.has(id))fail(400,'Stream IDs must be unique.');ids.add(id);
    const url=publicURL(stream.url,'Stream URL');if(urls.has(url))fail(400,'Each stream URL must be unique within the station.');urls.add(url);
    if(!['hls','mp3','aac','flac','ogg','other','unknown'].includes(stream.format))fail(400,'Choose a valid stream format.');
    const headers=stream.request_headers??{};if(!headers||typeof headers!=='object'||Array.isArray(headers))fail(400,'Stream headers must be an object.');
    const cleanHeaders={};for(const [k,v] of Object.entries(headers)){if(!['user-agent','referer'].includes(k.toLowerCase()))fail(400,'Only User-Agent and Referer stream headers are supported.');const h=text(v,'Header',1024);if(/[\r\n]/.test(h))fail(400,'Header values cannot contain newlines.');if(h)cleanHeaders[k.toLowerCase()]=h;}
    return {id,url,label:text(stream.label??'','Stream label',120),format:stream.format,enabled:stream.enabled!==false,request_headers:cleanHeaders};
  });
  station.preferred_stream_id=value.preferred_stream_id||null;
  if(station.preferred_stream_id&&!station.streams.some(s=>s.id===station.preferred_stream_id&&s.enabled))fail(400,'The preferred stream must be an enabled stream belonging to this station.');
  if(station.status==='published'&&!station.preferred_stream_id)fail(400,'Choose an enabled preferred stream before publishing.');
  return station;
}
export function mapStream(row, admin=false){
  const data={id:row.id,url:row.url,label:row.label,format:row.format,codec:row.codec,bitrate_kbps:row.bitrate_kbps,sample_rate_hz:row.sample_rate_hz,channels:row.channels,verification_status:row.verification_status,checked_at:row.checked_at,request_headers:JSON.parse(row.request_headers_json)};
  if(admin)Object.assign(data,{enabled:!!row.enabled,source_name:row.source_name,source_url:row.source_url,decoded_seconds:row.decoded_seconds,evidence:JSON.parse(row.evidence_json),test:row.test_status?{status:row.test_status,requested_at:row.test_requested_at,started_at:row.test_started_at,completed_at:row.test_completed_at,result:parseJSON(row.test_result_json,{}),error:row.test_error||''}:null});
  return data;
}
export function mapStation(row, streams, admin=false){
  const result={id:row.id,name:row.name,network:row.network,country:row.country,state:row.state,cities:JSON.parse(row.cities_json),tags:JSON.parse(row.tags_json),frequency:row.frequency||'',tagline:row.tagline||'',genres:JSON.parse(row.genres_json||'[]'),description:row.description,website_url:row.website_url,logo_url:row.logo_url,contact:JSON.parse(row.contact_json||'{}'),preferred_stream_id:row.preferred_stream_id,updated_at:row.updated_at,streams:streams.map(s=>mapStream(s,admin))};
  if(admin)Object.assign(result,{status:row.status,version:row.version,editorial_notes:row.editorial_notes,aliases:JSON.parse(row.aliases_json),research_id:row.research_id,updated_by:row.updated_by,merge_archive:parseJSON(row.merge_archive_json,[])});
  return result;
}
function integer(value,fallback,max){if(value===null)return fallback;if(!/^\d+$/.test(value))fail(400,'Pagination values must be positive integers.');const n=Number(value);if(n<1||n>max)fail(400,`Pagination value must be between 1 and ${max}.`);return n;}
export async function listStations(db,url,admin=false){
  const p=url.searchParams,params=[],where=[];const page=integer(p.get('page'),1,1000000),pageSize=integer(p.get('page_size'),50,100);
  if(!admin)where.push("s.status='published' AND EXISTS(SELECT 1 FROM streams p WHERE p.id=s.preferred_stream_id AND p.station_id=s.id AND p.enabled=1)");
  else if(p.get('status')){if(!statuses.includes(p.get('status')))fail(400,'Unknown station status.');where.push('s.status=?');params.push(p.get('status'));}
  for(const key of ['network','state'])if(p.get(key)){where.push(`s.${key}=?`);params.push(text(p.get(key),key,100));}
  if(p.get('city')){where.push('EXISTS(SELECT 1 FROM json_each(s.cities_json) WHERE value=? COLLATE NOCASE)');params.push(text(p.get('city'),'City',80));}
  if(p.get('q')){const q=text(p.get('q'),'Search',160).replace(/[\\%_]/g,'\\$&');where.push("(s.name LIKE ? ESCAPE '\\' OR s.network LIKE ? ESCAPE '\\' OR s.cities_json LIKE ? ESCAPE '\\' OR s.aliases_json LIKE ? ESCAPE '\\')");for(let i=0;i<4;i++)params.push('%'+q+'%');}
  const clause=where.length?' WHERE '+where.join(' AND '):'';
  const selectedSQL='SELECT s.id FROM stations s'+clause+' ORDER BY s.name COLLATE NOCASE,s.id LIMIT ? OFFSET ?';
  const streamSelect=admin?'SELECT st.*,t.status AS test_status,t.requested_at AS test_requested_at,t.started_at AS test_started_at,t.completed_at AS test_completed_at,t.result_json AS test_result_json,t.error AS test_error FROM streams st LEFT JOIN stream_tests t ON t.stream_id=st.id':'SELECT st.* FROM streams st';
  const [counts,rows,meta,streamRows]=await db.batch([db.prepare('SELECT COUNT(*) AS total FROM stations s'+clause).bind(...params),db.prepare('SELECT s.* FROM stations s'+clause+' ORDER BY s.name COLLATE NOCASE,s.id LIMIT ? OFFSET ?').bind(...params,pageSize,(page-1)*pageSize),db.prepare('SELECT revision,updated_at FROM catalogue_meta WHERE id=1'),db.prepare(streamSelect+' WHERE st.station_id IN ('+selectedSQL+')'+(admin?'':' AND st.enabled=1')+' ORDER BY st.station_id,st.id').bind(...params,pageSize,(page-1)*pageSize)]);
  const streams=streamRows.results;
  return {schema_version:1,...meta.results[0],page,page_size:pageSize,total:counts.results[0].total,has_more:page*pageSize<counts.results[0].total,stations:rows.results.map(row=>mapStation(row,streams.filter(s=>s.station_id===row.id),admin))};
}
export async function getStation(db,id,admin=false){
  const streamSQL=admin?'SELECT st.*,t.status AS test_status,t.requested_at AS test_requested_at,t.started_at AS test_started_at,t.completed_at AS test_completed_at,t.result_json AS test_result_json,t.error AS test_error FROM streams st LEFT JOIN stream_tests t ON t.stream_id=st.id WHERE st.station_id=? ORDER BY st.id':'SELECT * FROM streams WHERE station_id=? AND enabled=1 ORDER BY id';
  const [stationRows,streamRows]=await db.batch([db.prepare('SELECT * FROM stations WHERE id=?'+(admin?'':" AND status='published'")).bind(id),db.prepare(streamSQL).bind(id)]);
  const row=stationRows.results[0];if(!row)fail(404,'Station not found.');const streams=streamRows.results;
  if(!admin&&!streams.some(s=>s.id===row.preferred_stream_id))fail(404,'Station not available.');return mapStation(row,streams,admin);
}
export async function filters(db,admin=false){
  const condition=admin?'':" WHERE s.status='published' AND EXISTS(SELECT 1 FROM streams p WHERE p.id=s.preferred_stream_id AND p.station_id=s.id AND p.enabled=1)";
  const [networks,states,cities,counts]=await db.batch([
    db.prepare('SELECT DISTINCT network AS value FROM stations s'+condition+' ORDER BY value'),
    db.prepare('SELECT DISTINCT state AS value FROM stations s'+condition+' ORDER BY value'),
    db.prepare('SELECT DISTINCT j.value FROM stations s,json_each(s.cities_json) j'+condition+' ORDER BY value'),
    db.prepare('SELECT status,COUNT(*) AS count FROM stations s'+condition+' GROUP BY status')
  ]);
  return {networks:networks.results.map(r=>r.value).filter(Boolean),states:states.results.map(r=>r.value).filter(Boolean),cities:cities.results.map(r=>r.value).filter(Boolean),counts:counts.results};
}
export async function saveStation(request,db,editor,id){
  const input=await bodyJSON(request),value=validateStation(input),stamp=nowISO();const existing=id?await db.prepare('SELECT * FROM stations WHERE id=?').bind(id).first():null;
  if(id&&!existing)fail(404,'Station not found.');
  if(existing&&(!Number.isInteger(input.version)||input.version!==existing.version))fail(409,'Another editor has changed this station. Reload it before saving.');
  id=id||crypto.randomUUID();const version=existing?existing.version+1:1;
  const old=existing?(await db.prepare('SELECT * FROM streams WHERE station_id=?').bind(id).all()).results:[];
  const oldByID=new Map(old.map(stream=>[stream.id,stream]));
  const newIDs=value.streams.filter(stream=>!oldByID.has(stream.id)).map(stream=>stream.id);
  if(newIDs.length){const occupied=(await db.prepare(`SELECT id FROM streams WHERE id IN (${newIDs.map(()=>'?').join(',')})`).bind(...newIDs).all()).results;if(occupied.length)fail(400,'A new stream could not be saved because its identifier is already in use. Remove it and add the stream again.');}
  const statements=[];
  // A unique optimistic lock row makes the entire D1 batch roll back on a stale version.
  const mutation=crypto.randomUUID();
  statements.push(db.prepare('INSERT INTO mutation_locks (station_id,expected_version,mutation_id,guard) VALUES(?,?,?,CASE WHEN (?=0 AND NOT EXISTS(SELECT 1 FROM stations WHERE id=?)) OR EXISTS(SELECT 1 FROM stations WHERE id=? AND version=?) THEN 1 ELSE 0 END)').bind(id,existing?existing.version:0,mutation,existing?existing.version:0,id,id,existing?existing.version:0));
  if(existing)statements.push(db.prepare('UPDATE stations SET name=?,network=?,country=?,state=?,cities_json=?,tags_json=?,frequency=?,tagline=?,genres_json=?,description=?,website_url=?,logo_url=?,contact_json=?,status=?,preferred_stream_id=?,editorial_notes=?,version=?,updated_at=?,updated_by=? WHERE id=? AND version=?').bind(value.name,value.network,value.country,value.state,JSON.stringify(value.cities),JSON.stringify(value.tags),value.frequency,value.tagline,JSON.stringify(value.genres),value.description,value.website_url,value.logo_url,JSON.stringify(value.contact),value.status,value.preferred_stream_id,value.editorial_notes,version,stamp,editor.email,id,existing.version));
  else statements.push(db.prepare('INSERT INTO stations(id,name,network,country,state,cities_json,tags_json,frequency,tagline,genres_json,description,website_url,logo_url,contact_json,status,preferred_stream_id,editorial_notes,version,created_at,updated_at,updated_by) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)').bind(id,value.name,value.network,value.country,value.state,JSON.stringify(value.cities),JSON.stringify(value.tags),value.frequency,value.tagline,JSON.stringify(value.genres),value.description,value.website_url,value.logo_url,JSON.stringify(value.contact),value.status,value.preferred_stream_id,value.editorial_notes,version,stamp,stamp,editor.email));
  const retainedIDs=new Set(value.streams.map(stream=>stream.id));
  for(const prior of old)if(!retainedIDs.has(prior.id))statements.push(db.prepare('DELETE FROM streams WHERE id=? AND station_id=?').bind(prior.id,id));
  for(const stream of value.streams){
    const oldStream=oldByID.get(stream.id),headers=JSON.stringify(stream.request_headers);
    if(oldStream){
      const unchangedEvidence=oldStream.url===stream.url&&oldStream.request_headers_json===headers;
      statements.push(db.prepare('UPDATE streams SET url=?,label=?,format=?,enabled=?,request_headers_json=?,codec=?,bitrate_kbps=?,sample_rate_hz=?,channels=?,verification_status=?,checked_at=?,decoded_seconds=?,source_name=?,source_url=?,evidence_json=? WHERE id=? AND station_id=?').bind(stream.url,stream.label,stream.format,stream.enabled?1:0,headers,unchangedEvidence?oldStream.codec:'',unchangedEvidence?oldStream.bitrate_kbps:null,unchangedEvidence?oldStream.sample_rate_hz:null,unchangedEvidence?oldStream.channels:null,unchangedEvidence?oldStream.verification_status:'unverified',unchangedEvidence?oldStream.checked_at:null,unchangedEvidence?oldStream.decoded_seconds:null,unchangedEvidence?oldStream.source_name:'Editor',unchangedEvidence?oldStream.source_url:'',unchangedEvidence?oldStream.evidence_json:'{}',stream.id,id));
    }else statements.push(db.prepare('INSERT INTO streams(id,station_id,url,label,format,enabled,request_headers_json,codec,bitrate_kbps,sample_rate_hz,channels,verification_status,checked_at,decoded_seconds,source_name,source_url,evidence_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)').bind(stream.id,id,stream.url,stream.label,stream.format,stream.enabled?1:0,headers,'',null,null,null,'unverified',null,null,'Editor','','{}'));
  }
  statements.push(...await queueTests(db,id,value.streams,oldByID,editor.email));
  statements.push(db.prepare('UPDATE catalogue_meta SET revision=revision+1,updated_at=? WHERE id=1').bind(stamp));
  statements.push(db.prepare('INSERT INTO audit_log VALUES(?,?,?,?,?,?,?)').bind(mutation,editor.id,editor.email,existing?'station.updated':'station.created',id,JSON.stringify({before:existing?{...existing,streams:old.map(({id,url,label,format,enabled})=>({id,url,label,format,enabled}))}:null,after:{...value,version}}),stamp));
  // Locks are retained per version: concurrent writers cannot silently replace each other.
  try{await db.batch(statements);}catch(error){const message=String(error);if(message.includes('mutation_locks')||message.includes('guard'))fail(409,'Another editor has changed this station. Reload it before saving.');if(message.includes('UNIQUE constraint failed: streams.station_id, streams.url'))fail(400,'Each stream URL must be unique within the station.');throw error;}
  return json(await getStation(db,id,true),existing?200:201);
}

export async function mergeStations(request,db,editor){
  const input=await bodyJSON(request),targetID=text(input.target_id,'Destination station',120,true),sourceIDs=Array.isArray(input.source_ids)?[...new Set(input.source_ids.map(value=>text(value,'Duplicate station',120,true)))]:[];
  if(sourceIDs.length<1||sourceIDs.length>20||sourceIDs.includes(targetID))fail(400,'Choose one destination and between one and 20 different duplicate stations.');
  const ids=[targetID,...sourceIDs],versions=input.versions??{};
  const rows=(await db.prepare(`SELECT * FROM stations WHERE id IN (${ids.map(()=>'?').join(',')})`).bind(...ids).all()).results;
  if(rows.length!==ids.length)fail(404,'One or more selected stations no longer exist. Reload the station list.');
  for(const row of rows)if(!Number.isInteger(versions[row.id])||versions[row.id]!==row.version)fail(409,'A selected station has changed. Reload the station list before merging.');
  const target=rows.find(row=>row.id===targetID),sources=sourceIDs.map(id=>rows.find(row=>row.id===id));
  const streamRows=(await db.prepare(`SELECT * FROM streams WHERE station_id IN (${ids.map(()=>'?').join(',')}) ORDER BY station_id,id`).bind(...ids).all()).results;
  const targetStreams=streamRows.filter(stream=>stream.station_id===targetID),urlToRetained=new Map(targetStreams.map(stream=>[stream.url,stream]));
  const moved=[],duplicates=[];
  for(const source of sources)for(const stream of streamRows.filter(item=>item.station_id===source.id)){
    const retained=urlToRetained.get(stream.url);
    if(retained){duplicates.push({source:stream,retained});continue;}
    urlToRetained.set(stream.url,stream);moved.push(stream);
  }
  const firstUseful=(key,unknown=false)=>[target,...sources].map(row=>String(row[key]??'').trim()).find(value=>value&&(!unknown||value!=='Unknown'))||'Unknown';
  const targetContact=parseJSON(target.contact_json,{}),mergedContact={...targetContact};
  for(const key of ['talkback_phone','sms','office_phone'])mergedContact[key]=uniqueText([targetContact[key],...sources.map(row=>parseJSON(row.contact_json,{})[key])]).join('; ');
  for(const key of ['email','address','contact_page'])if(!String(mergedContact[key]??'').trim())mergedContact[key]=sources.map(row=>parseJSON(row.contact_json,{})[key]).find(Boolean)||'';
  const stamp=nowISO(),mutation=crypto.randomUUID(),archive=parseJSON(target.merge_archive_json,[]);
  archive.push(...sources.map(source=>({merged_at:stamp,source:{...source,streams:streamRows.filter(stream=>stream.station_id===source.id)}})));
  const aliases=uniqueText([parseJSON(target.aliases_json,[]),target.name,...sources.flatMap(row=>[row.name,...parseJSON(row.aliases_json,[])])]);
  const cities=uniqueText([parseJSON(target.cities_json,[]),...sources.map(row=>parseJSON(row.cities_json,[]))]);
  const tags=uniqueText([parseJSON(target.tags_json,[]),...sources.map(row=>parseJSON(row.tags_json,[]))]);
  const genres=uniqueText([parseJSON(target.genres_json,[]),...sources.map(row=>parseJSON(row.genres_json,[]))]);
  let preferred=target.preferred_stream_id;
  if(!preferred){for(const source of sources){if(!source.preferred_stream_id)continue;const sourceStream=streamRows.find(stream=>stream.id===source.preferred_stream_id);if(sourceStream){preferred=urlToRetained.get(sourceStream.url)?.id;break;}}}
  const statements=[];
  for(const row of rows)statements.push(db.prepare('INSERT INTO mutation_locks (station_id,expected_version,mutation_id,guard) VALUES(?,?,?,CASE WHEN EXISTS(SELECT 1 FROM stations WHERE id=? AND version=?) THEN 1 ELSE 0 END)').bind(row.id,row.version,`${mutation}-${row.id}`,row.id,row.version));
  statements.push(db.prepare('UPDATE stations SET network=?,country=?,state=?,cities_json=?,tags_json=?,frequency=?,tagline=?,genres_json=?,description=?,website_url=?,logo_url=?,contact_json=?,preferred_stream_id=?,aliases_json=?,editorial_notes=?,merge_archive_json=?,version=?,updated_at=?,updated_by=? WHERE id=? AND version=?').bind(firstUseful('network',true)==='Unknown'?'':firstUseful('network',true),target.country||firstUseful('country'),firstUseful('state',true),JSON.stringify(cities),JSON.stringify(tags),target.frequency||firstUseful('frequency',true).replace('Unknown',''),target.tagline||firstUseful('tagline',true).replace('Unknown',''),JSON.stringify(genres),target.description||firstUseful('description',true).replace('Unknown',''),target.website_url||firstUseful('website_url',true).replace('Unknown',''),target.logo_url||firstUseful('logo_url',true).replace('Unknown',''),JSON.stringify(mergedContact),preferred,JSON.stringify(aliases),target.editorial_notes,JSON.stringify(archive),target.version+1,stamp,editor.email,target.id,target.version));
  for(const stream of moved)statements.push(db.prepare('UPDATE streams SET station_id=? WHERE id=? AND station_id=?').bind(targetID,stream.id,stream.station_id));
  for(const pair of duplicates){
    const sourceRank=pair.source.verification_status==='audio_decoded'?2:pair.source.verification_status==='unverified'?1:0,targetRank=pair.retained.verification_status==='audio_decoded'?2:pair.retained.verification_status==='unverified'?1:0;
    if(sourceRank>targetRank)statements.push(db.prepare('UPDATE streams SET codec=?,bitrate_kbps=?,sample_rate_hz=?,channels=?,verification_status=?,checked_at=?,decoded_seconds=?,source_name=?,source_url=?,evidence_json=? WHERE id=?').bind(pair.source.codec,pair.source.bitrate_kbps,pair.source.sample_rate_hz,pair.source.channels,pair.source.verification_status,pair.source.checked_at,pair.source.decoded_seconds,pair.source.source_name,pair.source.source_url,pair.source.evidence_json,pair.retained.id));
    statements.push(db.prepare('DELETE FROM streams WHERE id=? AND station_id=?').bind(pair.source.id,pair.source.station_id));
  }
  for(const source of sources)statements.push(db.prepare('DELETE FROM stations WHERE id=? AND version=?').bind(source.id,source.version));
  statements.push(db.prepare('UPDATE catalogue_meta SET revision=revision+1,updated_at=? WHERE id=1').bind(stamp));
  statements.push(db.prepare('INSERT INTO audit_log VALUES(?,?,?,?,?,?,?)').bind(mutation,editor.id,editor.email,'station.merged',targetID,JSON.stringify({target_id:targetID,source_ids:sourceIDs,moved_streams:moved.map(stream=>stream.id),duplicate_streams:duplicates.map(pair=>pair.source.id),preserved_in_merge_archive:true}),stamp));
  try{await db.batch(statements);}catch(error){const message=String(error);if(message.includes('mutation_locks')||message.includes('guard'))fail(409,'A selected station changed during the merge. Reload the station list and try again.');throw error;}
  return json(await getStation(db,targetID,true),200);
}
