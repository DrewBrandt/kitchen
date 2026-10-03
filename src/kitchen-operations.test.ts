// @vitest-environment node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import Ajv from 'ajv';
import { describe, expect, it, vi } from 'vitest';
import { parse } from 'yaml';
import yaml from '../docs/pantry-gpt-openapi.yaml?raw';
import generated from '../supabase/functions/kitchen-mcp/operation-schemas.json';
import { operationTools } from '../supabase/functions/kitchen-mcp/operations';
import { registerTools } from '../supabase/functions/kitchen-mcp/tools';
const id='10000000-0000-4000-8000-000000000001';
function sample(s: any): any {
  if(s.oneOf) return sample(s.oneOf[0]);
  if(s.enum) return s.enum[0];
  const type=Array.isArray(s.type)?s.type.find((x:string)=>x!=='null'):s.type;
  if(type==='object')return Object.fromEntries((s.required??[]).map((key:string)=>[key,sample(s.properties[key])]));
  if(type==='array')return Array.from({length:s.minItems??1},()=>sample(s.items));
  if(type==='number'||type==='integer')return Math.max(1,s.minimum??0,(s.exclusiveMinimum??0)+1);
  if(type==='boolean')return false;
  return s.format==='uuid'?id:s.format==='date'?'2026-10-04':s.format==='date-time'?'2026-10-04T12:30:00-04:00':s.format==='uri'?'https://example.test/source':'Synthetic fixture';
}
function fixture(respond: typeof fetch=async()=>Response.json({status:'saved',id})) {
  const calls=new Map<string,{config:any;run:(args:unknown)=>Promise<any>}>();
  const server={registerTool:(name:string,config:unknown,run:any)=>calls.set(name,{config,run})} as unknown as McpServer;
  const fetcher=vi.fn<typeof fetch>(respond);const audit=vi.fn();
  registerTools(server,operationTools,{supabaseUrl:'https://synthetic.supabase.co',pantryToken:'server-only-fixture',fetch:fetcher,requestId:'audit-id',audit});
  return {calls,fetcher,audit};
}
describe('Kitchen operation contracts',()=>{
  it('advertises valid schemas without description fragments becoming keywords',async()=>{
    const server=new McpServer({name:'schema-check',version:'1'});
    registerTools(server,operationTools,{supabaseUrl:'https://synthetic.invalid',pantryToken:'unused',requestId:'schema-check',audit:()=>{},fetch:async()=>{throw new Error('No API call expected');}});
    const client=new Client({name:'schema-reader',version:'1'});const [a,b]=InMemoryTransport.createLinkedPair();
    await server.connect(a);await client.connect(b);
    try {
      const {tools}=await client.listTools();
      const ajv=new Ajv({strictSchema:true,strictTypes:false,validateFormats:false});
      for(const tool of tools)expect(()=>ajv.compile(tool.inputSchema),tool.name).not.toThrow();
      const log=tools.find(tool=>tool.name==='log_manual_consumption')!;
      expect((log.inputSchema.properties!.nutritionEstimate as Record<string,unknown>).description).toBe('Required when nutrition.estimated is true; include confidence, rationale, and optional per-nutrient min/max ranges.');
      expect(log.annotations).toMatchObject({readOnlyHint:false,destructiveHint:false,idempotentHint:true,openWorldHint:false});
      const undo=tools.find(tool=>tool.name==='void_consumption')!;
      expect((undo.inputSchema.properties!.reason as Record<string,unknown>).description).toBe('Why the event is being voided, such as duplicate entry.');
    } finally {await client.close();await server.close();}
  });
  it('keeps generated argument contracts synchronized with the existing OpenAPI',()=>{
    const contract=parse(yaml);
    for(const tool of generated){const original=structuredClone(contract.paths[tool.path][tool.method.toLowerCase()].requestBody.content['application/json'].schema);
      if(tool.path.includes('{id}')){original.properties={id:{type:'string',format:'uuid',description:'Exact existing record ID returned by a read.'},...original.properties};original.required=[...new Set(['id',...(original.required??[])])];}
      expect(tool.schema,tool.name).toEqual(original);
    }
    expect(operationTools).toHaveLength(19);
    expect(operationTools.map(t=>t.name)).not.toContain('save_preferences');
  });
  it.each(generated)('validates and forwards $name once without changing domain arguments',async tool=>{
    const f=fixture();const args=sample(tool.schema);
    if(tool.method==='PATCH'){const [key,value]=Object.entries(tool.schema.properties).find(([key])=>key!=='id')!;args[key]=sample(value);}
    const out=await f.calls.get(tool.name)!.run(args);expect(out.isError).not.toBe(true);
    expect(f.fetcher).toHaveBeenCalledTimes(1);const [url,request]=f.fetcher.mock.calls[0];
    expect(String(url)).toBe('https://synthetic.supabase.co/functions/v1/pantry-api'+tool.path.replace('{id}',id));
    const expected={...args};if(tool.path.includes('{id}'))delete expected.id;
    expect(request?.method).toBe(tool.method);expect(JSON.parse(String(request?.body))).toEqual(expected);
    expect(out.structuredContent.auditRequestId).toBe('audit-id');
    expect(f.calls.get(tool.name)!.config.annotations).toMatchObject({readOnlyHint:tool.readOnly,destructiveHint:tool.destructive,idempotentHint:tool.readOnly||tool.deduplicated,openWorldHint:false});
    if(!tool.readOnly)await expect(f.calls.get(tool.name)!.run({})).rejects.toThrow();
  });
  it('preserves a caller retry UUID, never retries automatically, and does not leak fetch errors',async()=>{
    const f=fixture(async()=>{throw new Error('PRIVATE_TOKEN transport failure');});
    const args={requestId:id,batchId:id,servings:1,timestamp:'2026-10-04T12:30:00-04:00',timePrecision:'exact'};
    const tool=f.calls.get('consume_prepared')!;
    expect(tool.config.annotations.idempotentHint).toBe(true);
    const failed=await tool.run(args);expect(failed.isError).toBe(true);expect(JSON.stringify(failed)).not.toContain('PRIVATE_TOKEN');expect(f.fetcher).toHaveBeenCalledTimes(1);
    await tool.run(args);expect(f.fetcher).toHaveBeenCalledTimes(2);
    expect(f.fetcher.mock.calls.map(([,init])=>JSON.parse(String(init?.body)).requestId)).toEqual([id,id]);
    expect(f.calls.get('save_meal_plan')!.config.annotations.idempotentHint).toBe(false);
    expect(f.calls.get('add_grocery_item')!.config.annotations.idempotentHint).toBe(false);
  });
  it('rejects empty patches, incomplete week replacements and unsafe arbitrary properties',async()=>{
    const f=fixture();
    await expect(f.calls.get('edit_recipe')!.run({id})).rejects.toThrow();
    await expect(f.calls.get('save_meal_plan')!.run({mode:'replaceWeek',entries:[]})).rejects.toThrow();
    await expect(f.calls.get('add_grocery_item')!.run({name:'Test',url:'https://evil.invalid'})).rejects.toThrow();
    expect(f.fetcher).not.toHaveBeenCalled();
  });
  it('returns actionable sanitized validation errors and keeps preview read-only',async()=>{
    const f=fixture(async()=>Response.json({error:'Insufficient stock; PRIVATE_TOKEN internal SQL'},{status:422}));
    const input=sample(generated.find(t=>t.name==='consume_inventory')!.schema);
    const result=await f.calls.get('consume_inventory')!.run(input);
    expect(result.content[0].text).toContain('Read current stock');expect(result.content[0].text).not.toContain('PRIVATE_TOKEN');
    expect(f.calls.get('preview_daily_nutrition')!.config.annotations).toMatchObject({readOnlyHint:true,destructiveHint:false,idempotentHint:true});
  });
});
