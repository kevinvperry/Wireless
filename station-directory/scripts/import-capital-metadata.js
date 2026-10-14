import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const source=JSON.parse(fs.readFileSync(path.join(root,'../research/australian-radio/capital-cities-metadata.json'),'utf8'));
const quote=value=>value===null||value===undefined?'NULL':"'"+String(value).replaceAll("'","''")+"'";
const stamp=new Date().toISOString();
const statements=[];
for(const station of source.stations){
  const basename=path.basename(station.artwork.local_file);
  const contact=Object.fromEntries(Object.entries(station.contact||{}).map(([key,value])=>[key,value??'']));
  const values={frequency:station.frequency??'',tagline:station.tagline??'',genres_json:JSON.stringify(station.genres??[]),description:station.description??'',website_url:station.website??'',logo_url:`https://wireless-directory.kevin-453.workers.dev/artwork/${basename}.png`,contact_json:JSON.stringify(contact)};
  statements.push(`UPDATE stations SET frequency=${quote(values.frequency)},tagline=${quote(values.tagline)},genres_json=${quote(values.genres_json)},description=${quote(values.description)},website_url=${quote(values.website_url)},logo_url=${quote(values.logo_url)},contact_json=${quote(values.contact_json)},version=version+1,updated_at=${quote(stamp)},updated_by='capital-metadata-import' WHERE research_id=${quote(station.id)};`);
}
statements.push(`INSERT OR REPLACE INTO import_runs(id,source,imported_at,record_count) VALUES('capital-metadata-2026-10-10',${quote(source.based_on)},${quote(stamp)},${source.stations.length});`);
statements.push(`UPDATE catalogue_meta SET revision=revision+1,updated_at=${quote(stamp)} WHERE id=1;`);
fs.mkdirSync(path.join(root,'generated'),{recursive:true});
fs.writeFileSync(path.join(root,'generated/capital-metadata.sql'),statements.join('\n')+'\n');
console.log({records:source.stations.length,generated:'generated/capital-metadata.sql'});
