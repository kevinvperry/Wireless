import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const source=JSON.parse(fs.readFileSync(path.join(root,'../research/australian-radio/directory.json'),'utf8'));
const quote=value=>value===null||value===undefined?'NULL':typeof value==='number'?String(value):"'"+String(value).replaceAll("'","''")+"'";
const sha=value=>createHash('sha256').update(value).digest('hex').slice(0,24);
const timestamp=new Date().toISOString(),statements=[];let published=0,streamCount=0;
const insert=(table,columns,values,tail='')=>statements.push(`INSERT OR IGNORE INTO ${table} (${columns.join(',')}) SELECT ${values.map(quote).join(',')}${tail};`);
for(const row of source.stations){
  const id='station_'+row.id;const preferred=row.preferred&&!row.identity_review?row.preferred:null;
  const status=preferred?'published':'draft';if(preferred)published++;
  const streamID=url=>'stream_'+sha(id+'\n'+url);
  const site=row.streams.map(s=>s.homepage).find(s=>s?.startsWith('https://'))||'';
  const notes=[row.identity_review, ...new Set(row.streams.map(s=>s.identity_note).filter(Boolean))].filter(Boolean).join('\n');
  insert('stations',['id','name','network','country','state','cities_json','tags_json','description','website_url','logo_url','status','preferred_stream_id','research_id','aliases_json','editorial_notes','created_at','updated_at'],[id,row.name.slice(0,160),row.network,'AU',row.state||'',JSON.stringify(row.cities||[]),'[]','',site,'',status,preferred?streamID(preferred.url):null,row.id,JSON.stringify(row.aliases||[]),notes,timestamp,timestamp]);
  for(const stream of row.streams){
    const c=stream.check||{},codec=c.codec||'';const format=c.transport==='HLS'?'hls':codec.startsWith('mp3')?'mp3':codec==='aac'?'aac':codec==='flac'?'flac':codec.includes('vorbis')||codec.includes('opus')?'ogg':'unknown';
    const headers=Object.fromEntries(Object.entries(stream.headers||{}).map(([k,v])=>[k.toLowerCase(),String(v).trim()]).filter(([k,v])=>v&&['user-agent','referer'].includes(k)));
    insert('streams',['id','station_id','url','label','format','codec','bitrate_kbps','sample_rate_hz','channels','enabled','verification_status','checked_at','decoded_seconds','request_headers_json','source_name','source_url','evidence_json'],[streamID(stream.url),id,stream.url,stream.source,format,codec,c.measured_kbps??null,c.sample_rate_hz??null,c.channels??null,c.status==='audio_decoded'&&!stream.identity_note?1:0,['audio_decoded','failed'].includes(c.status)?c.status:'unverified',c.checked_at??null,c.decoded_seconds??null,JSON.stringify(headers),stream.source,stream.source_url,JSON.stringify({...c,identity_note:stream.identity_note||null,derivation:stream.derivation||null})],` WHERE EXISTS (SELECT 1 FROM stations WHERE id=${quote(id)} AND version=1 AND updated_by='research-import')`);streamCount++;
  }
}
insert('import_runs',['id','source','imported_at','record_count'],['research-2026-10-10',source.summary.generated_at,timestamp,source.stations.length]);
statements.push(`UPDATE catalogue_meta SET revision=revision+1,updated_at=${quote(timestamp)} WHERE id=1;`);
fs.mkdirSync(path.join(root,'generated'),{recursive:true});fs.writeFileSync(path.join(root,'generated/research.sql'),statements.join('\n')+'\n');
const summary={stations:source.stations.length,published,drafts:source.stations.length-published,streams:streamCount,source_date:source.summary.generated_at,prepared_at:timestamp};
fs.writeFileSync(path.join(root,'generated/import-summary.json'),JSON.stringify(summary,null,2)+'\n');console.log(summary);
