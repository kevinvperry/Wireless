import {test} from 'node:test';
import assert from 'node:assert/strict';
import {qualityScore,compareQuality,analyseHLSPlaylist} from '../src/stream-testing.js';

test('quality scoring is codec aware and favours stable stereo HTTPS streams',()=>{
 const mp3=qualityScore({codec:'mp3',bitrate_kbps:128,channels:2,sample_rate_hz:44100,stable:true,https:true});
 const aac=qualityScore({codec:'aac',bitrate_kbps:128,channels:2,sample_rate_hz:44100,stable:true,https:true});
 assert.ok(aac>mp3);
 assert.ok(qualityScore({codec:'flac',bitrate_kbps:900})>aac);
});

test('quality comparison uses a material threshold',()=>{
 assert.equal(compareQuality({codec:'aac',bitrate_kbps:128},[{id:'old',score:qualityScore({codec:'mp3',bitrate_kbps:128})}]).classification,'recommended');
 assert.equal(compareQuality({codec:'mp3',bitrate_kbps:128},[{id:'similar',score:qualityScore({codec:'mp3',bitrate_kbps:130})}]).classification,'similar');
 assert.equal(compareQuality({codec:'mp3',bitrate_kbps:64},[{id:'better',score:qualityScore({codec:'aac',bitrate_kbps:128})}]).classification,'lower');
});

test('HLS analysis reports duration variation, gaps and discontinuities',()=>{
 const result=analyseHLSPlaylist(`#EXTM3U
#EXT-X-TARGETDURATION:6
#EXTINF:6,
one.aac
#EXT-X-DISCONTINUITY
#EXTINF:3,
two.aac
#EXT-X-GAP
#EXTINF:6,
three.aac`,'https://radio.example/live/index.m3u8');
 assert.equal(result.segments.length,3);
 assert.equal(result.segments[0].url,'https://radio.example/live/one.aac');
 assert.equal(result.target_duration,6);
 assert.equal(result.gap_count,1);
 assert.equal(result.discontinuity_count,1);
 assert.equal(result.duration_variation_percent,40);
});
