import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const source=JSON.parse(fs.readFileSync(path.join(root,'../research/australian-radio/capital-cities-metadata.json'),'utf8'));
const quote=value=>"'"+String(value).replaceAll("'","''")+"'";
const stamp=new Date().toISOString(),statements=[];
const keys=['talkback_phone','sms','office_phone','email','address','contact_page'];
for(const station of source.stations){
  const contact=Object.fromEntries(keys.map(key=>[key,station.contact?.[key]??'']));
  const json=JSON.stringify(contact);
  statements.push(`UPDATE stations SET contact_json=${quote(json)},version=version+1,updated_at=${quote(stamp)},updated_by='contact-metadata-import' WHERE research_id=${quote(station.id)} AND contact_json<>${quote(json)};`);
}
statements.push(`INSERT OR REPLACE INTO import_runs(id,source,imported_at,record_count) VALUES('contact-metadata-2026-10-10',${quote('capital-cities-metadata.csv and capital-cities-metadata.json')},${quote(stamp)},${source.stations.length});`);
statements.push(`UPDATE catalogue_meta SET revision=revision+1,updated_at=${quote(stamp)} WHERE id=1;`);
fs.mkdirSync(path.join(root,'generated'),{recursive:true});
fs.writeFileSync(path.join(root,'generated/contact-metadata.sql'),statements.join('\n')+'\n');
console.log({records:source.stations.length,generated:'generated/contact-metadata.sql'});
