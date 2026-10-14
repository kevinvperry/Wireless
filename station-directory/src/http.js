export class HTTPError extends Error {
  constructor(status, message, headers = {}) { super(message); this.status = status; this.headers = headers; }
}
export function json(data, status = 200, headers = {}) {
  return Response.json(data, {status, headers: {'Cache-Control':'no-store', ...headers}});
}
export function fail(status, message, headers) { throw new HTTPError(status, message, headers); }
export async function bodyJSON(request, maxBytes = 131072) {
  if (!(request.headers.get('Content-Type') || '').toLowerCase().startsWith('application/json')) fail(415,'Send JSON data.');
  if (Number(request.headers.get('Content-Length') || 0) > maxBytes) fail(413,'The request is too large.');
  const reader = request.body?.getReader(); if (!reader) fail(400,'JSON data is required.');
  const chunks=[]; let size=0;
  while (true) { const {done,value}=await reader.read(); if(done) break; size+=value.length; if(size>maxBytes){await reader.cancel();fail(413,'The request is too large.');} chunks.push(value); }
  const bytes=new Uint8Array(size); let offset=0; for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  try {const value=JSON.parse(new TextDecoder().decode(bytes)); if(!value || Array.isArray(value) || typeof value!=='object') fail(400,'Expected a JSON object.'); return value;}
  catch(error){if(error instanceof HTTPError)throw error;fail(400,'Invalid JSON.');}
}
export function sameOrigin(request) {
  if (request.headers.get('Origin') !== new URL(request.url).origin) fail(403,'This action must be made from the management page.');
}
export function secured(response) {
  const headers=new Headers(response.headers);
  headers.set('X-Content-Type-Options','nosniff'); headers.set('Referrer-Policy','no-referrer');
  headers.set('X-Frame-Options','DENY'); headers.set('Permissions-Policy','camera=(), microphone=(), geolocation=()');
  headers.set('Content-Security-Policy',"default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' https:; connect-src 'self'; font-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'");
  headers.set('Strict-Transport-Security','max-age=31536000');
  return new Response(response.body,{status:response.status,statusText:response.statusText,headers});
}
export const nowISO = () => new Date().toISOString();
export function text(value, key, max, required=false) {
  if(typeof value!=='string' || value.length>max || (required && !value.trim())) fail(400,`${key} must be ${required?'non-empty text':'text'} of at most ${max} characters.`);
  return value.trim();
}
export function publicURL(value, key, {optional=false, httpsOnly=false}={}) {
  const s=text(value,key,4096);if(optional&&!s)return '';
  let url;try{url=new URL(s);}catch{fail(400,`${key} must be a valid URL.`);}
  if(!(httpsOnly?['https:']:['http:','https:']).includes(url.protocol)||url.username||url.password)fail(400,`${key} must be a public HTTP${httpsOnly?'S':''} URL without embedded credentials.`);
  const host=url.hostname.toLowerCase().replace(/^\[|\]$/g,'');
  if(host==='localhost'||host.endsWith('.localhost')||host.endsWith('.local')||host==='::1'||host==='::'||host.startsWith('fc')&&host.includes(':')||host.startsWith('fd')&&host.includes(':')||host.startsWith('fe80:')||host.startsWith('::ffff:')||/^(?:0|10|127)\./.test(host)||/^169\.254\./.test(host)||/^192\.168\./.test(host)||/^172\.(?:1[6-9]|2\d|3[01])\./.test(host))fail(400,`${key} must not point to a local or private network.`);
  return s;
}
