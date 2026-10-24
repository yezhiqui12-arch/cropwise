import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
const source = readFileSync(new URL('./index.ts', import.meta.url), 'utf8');
const id = '11111111-1111-4111-8111-111111111111';
const basic = () => ({ model:'gemini-3.6-flash', body:{contents:[{role:'user',parts:[{text:'Hello'}]}]} });
function setup(options = {}) {
  let handler;
  const called = [], bodies = [];
  let claims = 0;
  vm.runInNewContext(source, {
    Deno: {env:{get:(key)=>({GEMINI_API_KEY:'test-only',SUPABASE_URL:'https://test.supabase.co',
      SUPABASE_SERVICE_ROLE_KEY:'service-test',GEMINI_ADVISOR_MODELS:options.policy ?? 'gemini-3.8-flash,gemini-3.5-flash-lite'})[key]},
      serve: callback => {handler = callback;}},
    Response, AbortSignal, TextDecoder, Uint8Array, setTimeout, clearTimeout,
    fetch: async (url, init) => {
      if (url.endsWith('/auth/v1/user')) {
        assert.equal(init.headers.Authorization, 'Bearer user-token');
        if (options.authThrow) throw Error('auth failed');
        return Response.json(options.user ?? {id,role:'authenticated',is_anonymous:true}, {status:options.authStatus ?? 200});
      }
      if (url.endsWith('/rpc/reserve_advisor_attempt')) {
        claims++;
        assert.deepEqual(JSON.parse(init.body),{p_user_id:id});
        assert.equal(init.headers.Authorization,'Bearer service-test');
        if (options.quotaThrow) throw Error('quota failed');
        return Response.json(options.quota?.(claims) ?? {allowed:true}, {status:options.quotaStatus ?? 200});
      }
      assert.ok(url.startsWith('https://generativelanguage.googleapis.com/'));
      called.push(url.match(/models\/([^:]+):/)[1]);
      bodies.push(JSON.parse(init.body));
      return options.provider?.(called.at(-1)) ?? Response.json({candidates:[]});
    },
  });
  const send = (payload=basic(), token='user-token') => handler(new Request('http://local',{
    method:'POST',headers:token ? {Authorization:`Bearer ${token}`} : {},
    body:typeof payload === 'string' ? payload : JSON.stringify(payload),
  }));
  return {send,handler,called,bodies,get claims(){return claims;}};
}
test('missing authorization makes no provider call', async()=>{
  const s=setup(); assert.equal((await s.send(basic(),null)).status,401); assert.equal(s.claims,0); assert.equal(s.called.length,0);
});
for(const status of [401,403]) test(`invalid/public key rejected by Auth (${status})`,async()=>{
  const s=setup({authStatus:status}); assert.equal((await s.send()).status,401); assert.equal(s.called.length,0);
});
test('no user or non-user role is rejected',async()=>{
  for(const user of [{role:'authenticated'},{id,role:'anon'},{id,role:'service_role'}]) {
    const s=setup({user}); assert.equal((await s.send()).status,401); assert.equal(s.claims,0);
  }
});
test('Auth outage fails closed',async()=>{const s=setup({authThrow:true});assert.equal((await s.send()).status,503);assert.equal(s.called.length,0);});
test('verified guest supported and server chooses approved model',async()=>{
  const s=setup();const r=await s.send();assert.equal(r.status,200);assert.equal((await r.json()).wormwiseModel,'gemini-3.8-flash');assert.deepEqual(s.called,['gemini-3.8-flash']);assert.equal(s.claims,1);
});
test('fallback reserves every attempt',async()=>{
  const s=setup({provider: m=>m==='gemini-3.8-flash'?Response.json({error:{message:'Model not found'}},{status:404}):Response.json({candidates:[]})});
  assert.equal((await s.send()).status,200);assert.equal(s.claims,2);assert.equal(s.called.length,2);
});
test('quota can stop a fallback before the second provider call',async()=>{
  const s=setup({quota:n=>n===1?{allowed:true}:{allowed:false,scope:'user',retry_after:15},provider:()=>Response.json({},{status:503})});
  const r=await s.send();assert.equal(r.status,429);assert.equal(r.headers.get('Retry-After'),'15');assert.equal((await r.json()).terminal,true);assert.equal(s.called.length,1);
});
for(const options of [{quotaThrow:true},{quotaStatus:500},{quota:()=>({})},{quota:()=>({allowed:false,scope:'project',retry_after:3600})}])
  test(`quota rejects before provider: ${JSON.stringify(options)}`,async()=>{
    const s=setup(options);assert.ok([429,503].includes((await s.send()).status));assert.equal(s.called.length,0);
  });
test('output capped, one candidate, optional store flag stripped',async()=>{
  const s=setup(),p=basic();p.body.store=false;p.body.generationConfig={maxOutputTokens:100000,temperature:.25,responseMimeType:'application/json',responseJsonSchema:{type:'object',properties:{answer:{type:'string'}}}};
  assert.equal((await s.send(p)).status,200);assert.equal(s.bodies[0].generationConfig.maxOutputTokens,2500);assert.equal(s.bodies[0].generationConfig.candidateCount,1);assert.equal('store' in s.bodies[0],false);
});
for(const mutate of [p=>p.body.tools=[],p=>p.body.contents[0].parts=[{inline_data:{data:'x'}}],p=>p.body.generationConfig={candidateCount:10},p=>p.body.generationConfig={thinkingConfig:{thinkingBudget:20000}},p=>p.model='gemini-3-pro',p=>p.body.generationConfig={maxOutputTokens:-1},p=>p.body.contents=Array(33).fill(p.body.contents[0])])
  test(`unsupported payload ${mutate.toString()}`,async()=>{
    const s=setup(),p=basic();mutate(p);assert.equal((await s.send(p)).status,400);assert.equal(s.claims,0);assert.equal(s.called.length,0);
  });
test('malformed JSON is 400',async()=>{const s=setup();assert.equal((await s.send('{')).status,400);assert.equal(s.claims,0);});
test('body and prompt size enforced before quota/provider',async()=>{
  for(const count of [80001,140000]) {const s=setup(),p=basic();p.body.contents[0].parts[0].text='x'.repeat(count);assert.equal((await s.send(p)).status,413);assert.equal(s.claims,0);}
});
test('invalid configured model policy fails closed',async()=>{const s=setup({policy:'gemini-3-pro'});assert.equal((await s.send()).status,503);assert.equal(s.claims,0);});
test('preview allowed in server policy',async()=>{const s=setup({policy:'gemini-3-flash-preview'});assert.equal((await s.send()).status,200);assert.deepEqual(s.called,['gemini-3-flash-preview']);});
test('provider errors are sanitized and terminal',async()=>{
  const s=setup({provider:()=>Response.json({error:{message:'private key/project detail'}},{status:400})});
  const r=await s.send();assert.equal(r.status,502);const p=await r.json();assert.equal(p.terminal,true);assert.equal(JSON.stringify(p).includes('private key'),false);
});
