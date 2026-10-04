// @vitest-environment node
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp';
import { describe, expect, it, vi } from 'vitest';
import { preparedPlanningContext, leftoverPlanningGuidance } from '../supabase/functions/kitchen-mcp/planning-context';
import { readTools, registerTools } from '../supabase/functions/kitchen-mcp/tools';
function fixture(response: () => Response = () => Response.json({ status: 'ok' })) {
  const calls = new Map<string, { config: any; run: (args: unknown) => Promise<any> }>();
  const server = { registerTool: (name: string, config: unknown, run: any) => calls.set(name, { config, run }) } as unknown as McpServer;
  const fetcher = vi.fn<typeof fetch>(async () => response()); const audit = vi.fn();
  registerTools(server, readTools, {supabaseUrl:'https://synthetic.supabase.co',pantryToken:'server-only-fixture',fetch:fetcher,requestId:'audit-fixture',audit});
  return { calls, fetcher, audit };
}
describe('Kitchen tool forwarding',()=>{
  it('returns storage context before unmodified prepared records, including old fridge and unknown/frozen data', async()=>{
    const batches = [
      { batchId: 'old-fridge', preparedAt: '2026-09-04T21:33:00Z', timePrecision: 'estimated', location: 'fridge', bestBy: null, servingsRemaining: 1.5, status: 'available' },
      { batchId: 'frozen', preparedAt: '2026-09-04T21:33:00Z', location: 'freezer', servingsRemaining: 2, status: 'available' },
      { batchId: 'unknown', preparedAt: null, location: null, bestBy: null, servingsRemaining: 1, status: 'available' },
    ];
    const f=fixture(()=>Response.json({batches,limit:20,offset:0,total:3,hasMore:false,nextOffset:null}));
    const result=await f.calls.get('get_prepared_foods')!.run({});
    expect(result.structuredContent.planningContext).toEqual(preparedPlanningContext);
    expect(result.structuredContent.result.batches).toEqual(batches);
    const text=result.content[0].text;
    expect(text.indexOf('planningContext')).toBeLessThan(text.indexOf('old-fridge'));
    expect(f.calls.get('get_prepared_foods')!.config.description).toContain(preparedPlanningContext.statusMeaning);
    expect(f.fetcher).toHaveBeenCalledTimes(1);
  });
  it('returns explicit leftover linkage instructions with plan reads',async()=>{
    const f=fixture(()=>Response.json({entries:[],limit:20,offset:0,total:0,hasMore:false,nextOffset:null}));
    const result=await f.calls.get('get_plan')!.run({});
    expect(result.structuredContent.planningContext).toEqual({leftoverPlanningGuidance});
    expect(f.fetcher).toHaveBeenCalledTimes(1);
  });

  it.each(readTools.filter(t=>!t.rowKey))('forwards fixed read route $name',async spec=>{
    const f=fixture();const args=spec.path.includes('{id}')?{id:'10000000-0000-4000-8000-000000000001'}:{};
    const output=await f.calls.get(spec.name)!.run(args);expect(output.isError).not.toBe(true);
    const [url,request] = f.fetcher.mock.calls[0] as unknown as [URL,RequestInit];
    expect(url.origin).toBe('https://synthetic.supabase.co');expect(request.method).toBe('GET');
    expect(request.headers).toMatchObject({authorization:'Bearer server-only-fixture'});
    expect(f.calls.get(spec.name)!.config.annotations).toMatchObject({readOnlyHint:true,idempotentHint:true,destructiveHint:false,openWorldHint:false});
  });
  it.each(readTools.filter(t=>t.rowKey))('validates bounded page for $name',async spec=>{
    const f=fixture(()=>Response.json({[spec.rowKey!]:[{id:'synthetic'}],limit:1,offset:0,total:2,hasMore:true,nextOffset:1}));
    expect((await f.calls.get(spec.name)!.run({limit:1})).structuredContent.result.nextOffset).toBe(1);
    const url=f.fetcher.mock.calls[0][0] as unknown as URL;expect(url.searchParams.get('limit')).toBe('1');
    expect(f.audit).toHaveBeenCalledWith(expect.objectContaining({tool:spec.name,count:1}));
    await expect(f.calls.get(spec.name)!.run({limit:51})).rejects.toThrow();expect(f.fetcher).toHaveBeenCalledTimes(1);
  });
  it('rejects malformed pages and strips internal failure details without retrying',async()=>{
    for(const response of [()=>Response.json({error:'PRIVATE_TOKEN postgres database detail'}, {status:422}),()=>new Response('PRIVATE_TOKEN invalid json',{status:422}),()=>Response.json({foods:[],limit:1,offset:0,total:3,hasMore:true,nextOffset:1})]){
      const f=fixture(response);const output=await f.calls.get('find_foods')!.run({limit:1});
      expect(output.isError).toBe(true);expect(JSON.stringify(output)).not.toContain('PRIVATE_TOKEN');expect(f.fetcher).toHaveBeenCalledTimes(1);
    }
  });
});
