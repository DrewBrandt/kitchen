// @vitest-environment node
import { createContext, runInContext } from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { describe, expect, it } from 'vitest';
import source from '../supabase/functions/pantry-api/index.ts?raw';
const uid = (n: number) => `10000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
type Row = Record<string, any>;
function fixture() {
  const tables: Record<string, Row[]> = {
    recipes: Array.from({ length: 53 }, (_, i) => ({ id: uid(i+1), name: `Recipe ${String(i).padStart(2,'0')}`, servings: 4 })),
    recipe_ingredients: [{ id: uid(101), recipe: uid(1), ingredient: uid(201), unit: uid(301), qty: 2, sort_order: 0, piece_basis: { count: 2, grams: 100 } }],
    base_foods: [{ id: uid(201), name: 'Rice', display_unit: uid(301), archived_at: null }],
    measure_conversions: [{ id: uid(301), short_name: 'g' }], products: [], inventory_lots: [], preps: [],
    meal_plans: [{ id: uid(401), plan_date: '2026-10-04', recipe: uid(1) }], planned_consumptions: [],
    shopping_items: [{ id: uid(501), free_text: 'Synthetic milk', source: 'manual', lot: null }], food_logs: [], inventory_events: [], inventory_event_costs: [],
  };
  const requests: { table: string; range?: number[]; filters: string[] }[] = [];
  const db = { from(table: string) {
    const record: {table: string; range?: number[]; filters: string[]} = { table, filters: [] }; requests.push(record);
    let rows = [...(tables[table] ?? [])], counted = false; const orders: string[] = [];
    const q: any = new Proxy({}, { get(_target, key) {
      if(key === 'then') return (yes: any, no: any) => {
        rows.sort((a,b) => { for(const field of orders) {if(a[field] !== b[field]) return a[field] < b[field] ? -1 : 1;} return 0; });
        return Promise.resolve({ data: record.range ? rows.slice(record.range[0],record.range[1]+1) : rows, count: counted ? rows.length : null, error: null }).then(yes,no);
      };
      return (...args: any[]) => {
        if(key === 'select') {
          counted = args[1]?.count === 'exact';
          if(args[0].includes('preps!inner')) rows=rows.filter(row=>tables.preps.some(prep=>prep.id===row.prep)).map(row=>({...row,'preps.voided_at':tables.preps.find(prep=>prep.id===row.prep)?.voided_at}));
        }
        if(key === 'range') record.range = args;
        if(key === 'order') orders.push(args[0]);
        if(['eq','in','is','gt','gte','lte','ilike'].includes(String(key))) {
          record.filters.push(String(key)+':'+args[0]);
          rows=rows.filter(r => key==='eq'||key==='is' ? r[args[0]]==args[1] : key==='in' ? args[1].includes(r[args[0]]) : key==='gt' ? r[args[0]]>args[1] : key==='gte' ? r[args[0]]>=args[1] : key==='lte' ? r[args[0]]<=args[1] : String(r[args[0]]).toLowerCase().includes(args[1].replaceAll('%','').toLowerCase()));
        }
        return q;
      };
    }}); return q;
  }};
  const ctx=createContext({Request,Response,URL,URLSearchParams});
  const transform = stripTypeScriptTypes as unknown as (code: string, options: { mode: 'transform' }) => string;
  runInContext(transform(source.replace(/^import .*\r?\n/, '').split('Deno.serve(')[0], {mode:'transform'}),ctx);
  return { tables, requests, read: async(path: string) => (await ctx.route(new Request('https://synthetic.invalid'+path),db)).json() };
}
describe('bounded Kitchen API reads', () => {
  it('pages at the database before hydrating only the selected recipes', async () => {
    const f=fixture(); const first=await f.read('/v1/recipes?limit=2');
    expect(first).toMatchObject({total:53,limit:2,offset:0,nextOffset:2,hasMore:true});
    expect(first.recipes[0].ingredients[0]).toMatchObject({food:'Rice',unit:{short_name:'g'},piece_basis:{count:2,grams:100}});
    expect(f.requests[0]).toMatchObject({table:'recipes',range:[0,1]});
    expect(f.requests.find(r=>r.table==='recipe_ingredients')).toMatchObject({range:[0,999],filters:['in:recipe']});
    const last=await f.read('/v1/recipes?limit=2&offset=52'); expect(last).toMatchObject({nextOffset:null,hasMore:false}); expect(last.recipes).toHaveLength(1);
  });
  it('resolves exact details beyond earlier pages and applies search before paging', async()=>{
    const f=fixture();expect((await f.read('/v1/recipes/'+uid(53))).recipe.id).toBe(uid(53));
    expect(await f.read('/v1/recipes?q=Recipe%2052&limit=1')).toMatchObject({total:1,hasMore:false});
  });
  it('keeps plans and manual groceries independently paged with date bounds',async()=>{
    const f=fixture();expect(await f.read('/v1/plans?collection=entries&from=2026-10-04&to=2026-10-04&limit=2')).toMatchObject({entries:[{source:'recipe',sourceId:uid(1)}],total:1});
    expect(await f.read('/v1/plans?collection=groceries&limit=2')).toMatchObject({groceries:[{source:'manual'}],total:1});
    expect(await f.read('/v1/plans?from=2026-10-05&limit=2')).toMatchObject({entries:[],total:0});
  });
  it('never silently truncates related records',async()=>{
    const f=fixture();f.tables.recipe_ingredients=Array.from({length:1001},(_,i)=>({id:uid(i+5000),recipe:uid(1)}));
    await expect(f.read('/v1/recipes?limit=1')).rejects.toThrow('safe read bound');
  });
  it('filters voided prepared batches before paging and preserves manual leftovers',async()=>{
    const f=fixture();f.tables.preps=[{id:uid(601),label:'Synthetic leftovers',servings:4,voided_at:null,prepped_at:'2026-09-04T21:33:00Z',time_precision:'estimated'},{id:uid(602),label:'Voided',voided_at:'2026-10-03'}];
    f.tables.inventory_lots=[{id:uid(701),prep:uid(601),remaining_qty:2,initial_qty:4,location:'fridge',use_by:null},{id:uid(702),prep:uid(602),remaining_qty:2,initial_qty:4}];
    expect(await f.read('/v1/prepared-batches?limit=1')).toMatchObject({batches:[{name:'Synthetic leftovers',sourceType:'manual',servingsRemaining:2,location:'fridge',preparedAt:'2026-09-04T21:33:00Z',timePrecision:'estimated',bestBy:null,status:'available'}],total:1,hasMore:false});
    expect(await f.read('/v1/prepared-batches?limit=1&includeVoided=true')).toMatchObject({total:2,hasMore:true,nextOffset:1});
  });
  it('hydrates history provenance only for the selected events',async()=>{
    const f=fixture();f.tables.food_logs=[{id:uid(801),occurred_at:new Date().toISOString(),voided_at:null}];
    f.tables.inventory_events=[{id:uid(802),food_log:uid(801),lot:uid(803),quantity_delta:-1}];
    f.tables.inventory_lots=[{id:uid(803),initial_qty:2,total_cost:8,out_of_pocket_cost:0,paid_by:'Gift giver',acquisition_type:'gift'}];
    f.tables.inventory_event_costs=[{inventory_event_id:uid(802),cost:4}];
    expect(await f.read('/v1/history?limit=1')).toMatchObject({total:1,events:[{totalPrice:4,outOfPocketCost:0,cost:4,paidBy:'Gift giver',acquisitionType:'gift'}]});
  });
  it.each(['limit=0','limit=51','offset=-1','limit=2&days=0'])('rejects invalid bounds %s',async params=>{await expect(fixture().read('/v1/history?'+params)).rejects.toThrow();});
  it('provides honest empty histories, batches, foods and products',async()=>{
    const f=fixture();for(const [path,key] of [['history','events'],['prepared-batches','batches'],['products','products']])expect(await f.read('/v1/'+path+'?limit=2')).toMatchObject({[key]:[],total:0,nextOffset:null});
    expect(await f.read('/v1/foods?limit=2')).toMatchObject({foods:[{name:'Rice',displayUnit:{short_name:'g'}}],total:1});
  });
});
