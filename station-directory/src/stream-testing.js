import {fail,json,nowISO} from './http.js';

const MAX_BYTES=768*1024;
const FETCH_TIMEOUT_MS=12000;
const codecWeights={flac:5,opus:2.2,aac:1.55,'he-aac':1.75,mp3:1,vorbis:1.15,unknown:.6};

function cleanCodec(value=''){
  const codec=String(value).toLowerCase();
  if(codec.includes('flac'))return 'flac';
  if(codec.includes('opus'))return 'opus';
  if(codec.includes('mp4a.40.5')||codec.includes('mp4a.40.29'))return 'he-aac';
  if(codec.includes('aac')||codec.includes('mp4a'))return 'aac';
  if(codec.includes('vorbis'))return 'vorbis';
  if(codec.includes('mp3')||codec.includes('mpeg'))return 'mp3';
  return 'unknown';
}
function formatFor(codec,transport){if(transport==='hls')return 'hls';return ['mp3','aac','flac','ogg'].includes(codec)?codec:codec==='vorbis'||codec==='opus'?'ogg':'unknown';}
function absoluteURL(value,base){try{return new URL(value,base).href;}catch{return null;}}
function attributes(line){const result={};for(const match of line.matchAll(/([A-Z0-9-]+)=("[^"]*"|[^,]*)/g))result[match[1]]=match[2].replace(/^"|"$/g,'');return result;}

export function qualityScore(result={}){
  const codec=cleanCodec(result.codec),bitrate=Number(result.bitrate_kbps)||0,channels=Number(result.channels)||0,sampleRate=Number(result.sample_rate_hz)||0;
  if(codec==='flac')return 100000+Math.min(bitrate,3000);
  return Math.round(bitrate*(codecWeights[codec]||codecWeights.unknown)+(channels>1?8:0)+(sampleRate>=44100?4:0)+(result.https?2:0)+(result.stable?6:0));
}
export function compareQuality(candidate,others=[]){
  const available=others.filter(item=>Number(item.score)>0),best=available.sort((a,b)=>b.score-a.score)[0];
  if(!best)return {classification:'first-tested',label:'First technically tested stream',difference_percent:null,compared_stream_id:null};
  const score=qualityScore(candidate),difference=Math.round((score-best.score)/best.score*100);
  if(difference>=12)return {classification:'recommended',label:'Higher encoded quality',difference_percent:difference,compared_stream_id:best.id};
  if(difference<=-12)return {classification:'lower',label:'Lower encoded quality',difference_percent:difference,compared_stream_id:best.id};
  return {classification:'similar',label:'Similar encoded quality',difference_percent:difference,compared_stream_id:best.id};
}

async function readLimited(response){
  if(!response.ok)throw new Error(`Stream returned HTTP ${response.status}.`);
  const reader=response.body?.getReader();if(!reader)return new Uint8Array(await response.arrayBuffer());
  const parts=[];let length=0;
  while(length<MAX_BYTES){const {done,value}=await reader.read();if(done)break;const remaining=MAX_BYTES-length,part=value.length>remaining?value.slice(0,remaining):value;parts.push(part);length+=part.length;if(length>=MAX_BYTES)break;}
  await reader.cancel().catch(()=>{});const output=new Uint8Array(length);let offset=0;for(const part of parts){output.set(part,offset);offset+=part.length;}return output;
}
async function fetchSample(url,headers={}){
  const started=Date.now();
  const response=await fetch(url,{headers:{Accept:'*/*','User-Agent':'Wireless Stream Tester/1.0',...headers},redirect:'follow',signal:AbortSignal.timeout(FETCH_TIMEOUT_MS)});
  const bytes=await readLimited(response);return {response,bytes,elapsed_ms:Date.now()-started};
}
function textBytes(bytes){return new TextDecoder().decode(bytes);}
function mp3Frame(bytes){
  const rates={1:[44100,48000,32000],2:[22050,24000,16000],2.5:[11025,12000,8000]},bitrates={1:[32,40,48,56,64,80,96,112,128,160,192,224,256,320],2:[8,16,24,32,40,48,56,64,80,96,112,128,144,160]};
  for(let i=0;i<Math.min(bytes.length-4,65536);i++){if(bytes[i]!==255||(bytes[i+1]&0xe0)!==0xe0)continue;const versionBits=(bytes[i+1]>>3)&3,layer=(bytes[i+1]>>1)&3,rateIndex=(bytes[i+2]>>4)&15,sampleIndex=(bytes[i+2]>>2)&3;if(layer!==1||rateIndex===0||rateIndex===15||sampleIndex===3||versionBits===1)continue;const version=versionBits===3?1:versionBits===2?2:2.5;return {codec:'mp3',bitrate_kbps:bitrates[version===1?1:2][rateIndex-1],sample_rate_hz:rates[version][sampleIndex],channels:((bytes[i+3]>>6)&3)===3?1:2};}return null;
}
function adtsFrame(bytes){
  const rates=[96000,88200,64000,48000,44100,32000,24000,22050,16000,12000,11025,8000,7350];
  for(let i=0;i<Math.min(bytes.length-7,65536);i++){if(bytes[i]!==255||(bytes[i+1]&0xf6)!==0xf0)continue;const sampleRate=rates[(bytes[i+2]>>2)&15],channels=((bytes[i+2]&1)<<2)|(bytes[i+3]>>6);if(!sampleRate)continue;let total=0,frames=0,pos=i;while(pos+7<bytes.length&&bytes[pos]===255&&(bytes[pos+1]&0xf6)===0xf0){const length=((bytes[pos+3]&3)<<11)|(bytes[pos+4]<<3)|(bytes[pos+5]>>5);if(length<7||pos+length>bytes.length)break;total+=length;frames++;pos+=length;}const bitrate=frames>1?Math.round(total*8*sampleRate/(frames*1024)/100)/10:null;return {codec:'aac',bitrate_kbps:bitrate,sample_rate_hz:sampleRate,channels:channels||null};}return null;
}
function sniff(bytes,contentType=''){
  if(bytes[0]===0x66&&bytes[1]===0x4c&&bytes[2]===0x61&&bytes[3]===0x43)return {codec:'flac'};
  if(bytes[0]===0x4f&&bytes[1]===0x67&&bytes[2]===0x67&&bytes[3]===0x53)return {codec:'vorbis'};
  return adtsFrame(bytes)||mp3Frame(bytes)||{codec:cleanCodec(contentType)};
}
export function analyseHLSPlaylist(playlist,baseURL){
  const lines=playlist.split(/\r?\n/).map(line=>line.trim()).filter(Boolean),segments=[];let duration=null,gap=false,discontinuity=false;
  for(const line of lines){
    if(line.startsWith('#EXTINF:'))duration=Number(line.slice(8).split(',')[0]);
    else if(line==='#EXT-X-GAP')gap=true;
    else if(line==='#EXT-X-DISCONTINUITY')discontinuity=true;
    else if(!line.startsWith('#')&&duration>0){segments.push({url:absoluteURL(line,baseURL),duration,gap,discontinuity});duration=null;gap=false;discontinuity=false;}
  }
  const durations=segments.map(segment=>segment.duration),average=durations.length?durations.reduce((sum,value)=>sum+value,0)/durations.length:0;
  const variation=average?Math.max(...durations.map(value=>Math.abs(value-average)))/average:0;
  return {segments,target_duration:Number(lines.find(line=>line.startsWith('#EXT-X-TARGETDURATION:'))?.split(':')[1])||null,duration_variation_percent:Math.round(variation*1000)/10,gap_count:segments.filter(segment=>segment.gap).length,discontinuity_count:segments.filter(segment=>segment.discontinuity).length};
}
async function inspectHLS(url,playlist,responseHeaders,requestHeaders){
  let mediaURL=url,bandwidth=null,codec='unknown';const lines=playlist.split(/\r?\n/).map(line=>line.trim()).filter(Boolean);
  const variants=[];for(let i=0;i<lines.length;i++)if(lines[i].startsWith('#EXT-X-STREAM-INF:')){const data=attributes(lines[i]);const next=lines.slice(i+1).find(line=>!line.startsWith('#'));if(next)variants.push({url:absoluteURL(next,url),bandwidth:Number(data.AVERAGE_BANDWIDTH||data.BANDWIDTH)||0,codec:cleanCodec(data.CODECS)});}
  if(variants.length){const selected=variants.sort((a,b)=>b.bandwidth-a.bandwidth)[0];mediaURL=selected.url;bandwidth=selected.bandwidth?Math.round(selected.bandwidth/100)/10:null;codec=selected.codec;const nested=await fetchSample(mediaURL,requestHeaders);playlist=textBytes(nested.bytes);}
  const analysis=analyseHLSPlaylist(playlist,mediaURL),samples=[];
  for(const segment of analysis.segments.filter(item=>item.url&&!item.gap).slice(-3)){
    const sample=await fetchSample(segment.url,requestHeaders),audio=sniff(sample.bytes,sample.response.headers.get('content-type')||'');
    codec=codec==='unknown'?audio.codec:codec;const segmentBytes=Number(sample.response.headers.get('content-length'))||sample.bytes.length;
    samples.push({duration:segment.duration,bytes:segmentBytes,download_ms:sample.elapsed_ms,download_ratio:Math.round(sample.elapsed_ms/1000/segment.duration*1000)/1000,bitrate_kbps:Math.round(segmentBytes*8/segment.duration/100)/10,codec:audio.codec,sample_rate_hz:audio.sample_rate_hz||null,channels:audio.channels||null});
  }
  const measured=samples.length?Math.round(samples.reduce((sum,item)=>sum+item.bitrate_kbps,0)/samples.length*10)/10:null;
  const sampleRate=samples.find(item=>item.sample_rate_hz)?.sample_rate_hz||null,channels=samples.find(item=>item.channels)?.channels||null;
  const maxDownloadRatio=samples.length?Math.max(...samples.map(item=>item.download_ratio)):null;
  const stable=samples.length>=2&&samples.every(item=>item.bytes>1024)&&analysis.gap_count===0&&maxDownloadRatio<0.8;
  const hlsHealth=analysis.gap_count>0||maxDownloadRatio>=1?'poor':!stable||analysis.duration_variation_percent>25||analysis.discontinuity_count>0?'warning':'good';
  return {transport:'hls',format:'hls',codec,bitrate_kbps:bandwidth||measured,sample_rate_hz:sampleRate,channels,stable,resolved_url:mediaURL,content_type:responseHeaders.get('content-type')||'',measurement:bandwidth?'playlist-advertised-and-segment-timing':'multi-segment-estimate',hls_health:hlsHealth,hls_segment_count:samples.length,hls_target_duration:analysis.target_duration,hls_duration_variation_percent:analysis.duration_variation_percent,hls_gap_count:analysis.gap_count,hls_discontinuity_count:analysis.discontinuity_count,hls_max_download_ratio:maxDownloadRatio,hls_segments:samples};
}
export async function inspectStream(url,requestHeaders={},depth=0){
  const started=Date.now(),{response,bytes}=await fetchSample(url,requestHeaders),contentType=response.headers.get('content-type')||'',body=textBytes(bytes),hls=body.includes('#EXTM3U')&&(body.includes('#EXTINF')||body.includes('#EXT-X-STREAM-INF'));
  if(!hls&&depth<2){const playlistMatch=body.match(/(?:^|\n)File\d+=(https?:\/\/[^\r\n]+)/i)||body.match(/(?:^|\n)(https?:\/\/[^#\s][^\r\n]*)/i);if(playlistMatch&&(contentType.includes('playlist')||contentType.includes('scpls')||/^\s*(?:#EXTM3U|\[playlist\])/i.test(body))){const nested=await inspectStream(playlistMatch[1].trim(),requestHeaders,depth+1);nested.playlist_url=url;return nested;}}
  const result=hls?await inspectHLS(response.url||url,body,response.headers,requestHeaders):{transport:'continuous',...sniff(bytes,contentType),stable:bytes.length>16384,resolved_url:response.url||url,content_type:contentType,measurement:'audio-frame-header'};
  result.format=formatFor(result.codec,result.transport);result.https=(result.resolved_url||url).startsWith('https:');result.startup_ms=Date.now()-started;result.bytes_sampled=bytes.length;result.sync_compatibility=result.transport==='continuous'?'preferred':'avplayer-preferred';result.score=qualityScore(result);return result;
}

export async function queueTests(db,stationID,streams,oldByID,actor){
  const stamp=nowISO(),statements=[];
  for(const stream of streams){const old=oldByID.get(stream.id),headers=JSON.stringify(stream.request_headers),changed=!old||old.url!==stream.url||old.request_headers_json!==headers;if(changed&&stream.url)statements.push(db.prepare("INSERT INTO stream_tests(stream_id,station_id,requested_url,status,requested_at,requested_by,result_json,error) VALUES(?,?,?,'queued',?,?,'{}','') ON CONFLICT(stream_id) DO UPDATE SET station_id=excluded.station_id,requested_url=excluded.requested_url,status='queued',requested_at=excluded.requested_at,started_at=NULL,completed_at=NULL,requested_by=excluded.requested_by,result_json='{}',error=''").bind(stream.id,stationID,stream.url,stamp,actor));}
  return statements;
}
export async function requestStreamTest(request,db,editor,stationID,streamID){
  const stream=await db.prepare('SELECT * FROM streams WHERE id=? AND station_id=?').bind(streamID,stationID).first();if(!stream)fail(404,'Stream not found.');const stamp=nowISO();await db.prepare("INSERT INTO stream_tests(stream_id,station_id,requested_url,status,requested_at,requested_by,result_json,error) VALUES(?,?,?,'queued',?,?,'{}','') ON CONFLICT(stream_id) DO UPDATE SET requested_url=excluded.requested_url,status='queued',requested_at=excluded.requested_at,started_at=NULL,completed_at=NULL,requested_by=excluded.requested_by,result_json='{}',error=''").bind(streamID,stationID,stream.url,stamp,editor.email).run();return json({status:'queued',stream_id:streamID},202);
}
export async function processPendingStreamTests(env,limit=2){
  if(env.STREAM_TESTING_DISABLED==='true')return;const jobs=(await env.DB.prepare("SELECT t.*,s.request_headers_json FROM stream_tests t JOIN streams s ON s.id=t.stream_id AND s.station_id=t.station_id AND s.url=t.requested_url WHERE t.status='queued' ORDER BY t.requested_at LIMIT ?").bind(limit).all()).results;
  for(const job of jobs){const started=nowISO();await env.DB.prepare("UPDATE stream_tests SET status='testing',started_at=? WHERE stream_id=? AND status='queued'").bind(started,job.stream_id).run();try{const result=await inspectStream(job.requested_url,JSON.parse(job.request_headers_json||'{}'));const peers=(await env.DB.prepare("SELECT s.id,s.codec,s.bitrate_kbps,s.sample_rate_hz,s.channels,s.evidence_json,t.result_json FROM streams s LEFT JOIN stream_tests t ON t.stream_id=s.id AND t.status='completed' WHERE s.station_id=? AND s.id<>? AND s.enabled=1").bind(job.station_id,job.stream_id).all()).results.map(row=>{const tested=JSON.parse(row.result_json||'{}');return {id:row.id,score:tested.score||qualityScore(row)};});result.comparison=compareQuality(result,peers);const completed=nowISO(),evidence=JSON.stringify({automated_test:result});await env.DB.batch([env.DB.prepare("UPDATE stream_tests SET status='completed',completed_at=?,result_json=?,error='' WHERE stream_id=? AND requested_url=?").bind(completed,JSON.stringify(result),job.stream_id,job.requested_url),env.DB.prepare("UPDATE streams SET format=?,codec=?,bitrate_kbps=?,sample_rate_hz=?,channels=?,checked_at=?,source_name='Wireless automated test',evidence_json=? WHERE id=? AND station_id=? AND url=?").bind(result.format,result.codec,result.bitrate_kbps,result.sample_rate_hz,result.channels,completed,evidence,job.stream_id,job.station_id,job.requested_url),env.DB.prepare('UPDATE catalogue_meta SET revision=revision+1,updated_at=? WHERE id=1').bind(completed)]);}catch(error){const completed=nowISO(),message=String(error?.message||error).slice(0,1000);await env.DB.prepare("UPDATE stream_tests SET status='failed',completed_at=?,error=?,result_json='{}' WHERE stream_id=? AND requested_url=?").bind(completed,message,job.stream_id,job.requested_url).run();}}
}
