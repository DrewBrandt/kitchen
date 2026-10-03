// @vitest-environment node
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp';
import { describe, expect, it, vi } from 'vitest';
import { readTools, registerTools } from '../supabase/functions/kitchen-mcp/tools';
function fixture(response: () => Response = () => Response.json({ status: 'ok' })) {
  const calls = new Map<string, { config: any; run: (args: unknown) => Promise<any> }>();
  const server = { registerTool: (name: string, config: unknown, run: any) => calls.set(name, { config, run }) } as unknown as McpServer;
  const fetcher = vi.fn<typeof fetch>(async () => response()); const audit = vi.fn();
  registerTools(server, readTools, {supabaseUrl:'https://synthetic.supabase.co',pantryToken:'server-only-fixture',fetch:fetcher,requestId:'audit-fixture',audit});
  return { calls, fetcher, audit };
}
describe('Kitchen tool forwarding',()=>{
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
