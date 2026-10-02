/// <reference types="node" />
// @vitest-environment node
import { createContext, runInContext } from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import Ajv2020 from 'ajv/dist/2020';
import { parse } from 'yaml';
import { expect, it } from 'vitest';
import edgeSource from '../supabase/functions/pantry-api/index.ts?raw';
import schemaText from '../docs/pantry-gpt-openapi.yaml?raw';
import { loadPantryData } from './lib/pantry-repository';

type Row = Record<string, any>;
const uuid = (n: number) => '98600000-0000-0000-0000-' + String(n).padStart(12, '0');
const units = [['g','weight',1],['oz','weight',.03527396195],['lb','weight',.00220462262],['fl oz','volume',1],['cup','volume',.125],['mL','volume',29.5735295625],['ct','discrete',1]].map(([short_name,measure_style,base_to_this_ratio],i)=>({id:uuid(10+i),short_name,measure_style,base_to_this_ratio}));
const unit = (name: string) => units.find(u=>u.short_name===name)!;
function fixture(style='weight', display='oz', remaining=453.5, initial=907, packageUnit='lb') {
  const lot: Row = { id:uuid(1),product:uuid(2),initial_qty:initial,remaining_qty:remaining,total_cost:8,out_of_pocket_cost:8,paid_by:'Fixture',cost_is_estimated:false,cost_source:'Synthetic receipt',price_as_of:'2026-10-01',acquisition_type:'grocery',location:'pantry',use_by:null,acquired_at:'2026-10-01T12:00:00Z',acquired_time_precision:'exact',note:null,piece_count:null,piece_basis_qty:null };
  const product: Row = {id:uuid(2),food:uuid(3),name:'Fixture package',brand:null,package_qty_base:initial,package_unit:unit(packageUnit).id,estimated_cost:12,cost_source:'Synthetic package estimate',cost_as_of:'2026-09-30',serving_qty_base:initial/4,nutrition_basis_qty:initial/4,servings_per_package:4,archived_at:null};
  const food: Row = {id:uuid(3),name:'Fixture food',measure_style:style,display_unit:unit(display).id};
  const tables: Record<string,Row[]> = {inventory_lots:[lot],products:[product],base_foods:[food],measure_conversions:structuredClone(units),personal_settings:[{time_zone:'UTC'}]};
  const db = {from(table: string) { let data: any = tables[table] ?? []; const query: any = new Proxy({}, {get(_target,key) { if(key==='then')return (yes: any,no: any)=>Promise.resolve({data,error:null}).then(yes,no);return (...args: any[])=>{if(key==='gt')data=data.filter((row: Row)=>Number(row[args[0]])>args[1]);if(key==='single')data=data[0];if(key==='is')data=data.filter((row: Row)=>row[args[0]]==args[1]);return query;};}});return query;}};
  const context=createContext({Request,Response,URL});
  const transform=stripTypeScriptTypes as unknown as (code:string,options:{mode:'transform'})=>string;
  runInContext(transform(edgeSource.replace(/^import .*\r?\n/,'').split('Deno.serve(')[0],{mode:'transform'}),context);
  const request=async(query='')=>{const response=await context.route(new Request('https://fixture.invalid/v1/inventory'+query),db) as Response;expect(response.status).toBe(200);return response.json();};
  return {lot,product,food,tables,request,app:()=>loadPantryData(db as Parameters<typeof loadPantryData>[0])};
}
const schema=parse(schemaText);
const ajv=new Ajv2020({strict:false,allErrors:true});ajv.addFormat('uuid',/^[0-9a-f-]{36}$/i);ajv.addFormat('date-time',()=>true);
ajv.addSchema({$id:'urn:test:inventory',components:schema.components});
const validate=ajv.compile({$ref:'urn:test:inventory#/components/schemas/InventoryResponse'});

it.each([
 ['weight','g',453.592,907,'lb','g',453.592],
 ['weight','oz',453.592,907,'lb','g',453.592*.03527396195],
 ['weight','lb',453.592,907,'oz','g',453.592*.00220462262],
 ['volume','fl oz',16.9070113509,33.8140227018,'mL','fl oz',16.9070113509],
 ['volume','cup',16,32,'fl oz','fl oz',2],
 ['volume','mL',16,32,'cup','fl oz',16*29.5735295625],
 ['discrete','ct',6,12,'ct','ct',6],
] as const)('pairs %s stock with %s and its package basis',async(style,display,remaining,initial,packageUnit,base,converted)=>{
 const f=fixture(style,display,remaining,initial,packageUnit);const body=await f.request();const row=body.lots[0];
 expect(validate(body),JSON.stringify(validate.errors)).toBe(true);
 expect(row.quantityBase).toBe(remaining);expect(row.baseUnit).toBe(base);expect(row.displayUnit).toBe(display);expect(row.displayQuantity).toBeCloseTo(converted,8);
 expect(row.initialQuantityBase).toBe(initial);expect(row.productPackage.quantityBase).toBe(initial);expect(row.productPackage.baseUnit).toBe(base);expect(row.productPackage.displayUnit).toBe(packageUnit);expect(row.productPackage.displayQuantity).toBeCloseTo(initial*Number(unit(packageUnit).base_to_this_ratio),8);
 const app=(await f.app()).inventorySections[0].foods[0];expect(row.displayQuantity).toBeCloseTo(app.lotDetails![0].remainingDisplay,8);expect(row.valuation.remainingValue).toBeCloseTo(app.cost!,8);
 // Existing fields retain their exact meaning and values.
 expect(row).toMatchObject({lotId:f.lot.id,productId:f.product.id,foodId:f.food.id,product:'Fixture package',food:'Fixture food',status:'available',totalPrice:8,outOfPocketCost:8,paidBy:'Fixture',costIsEstimated:false,costSource:'Synthetic receipt',priceAsOf:'2026-10-01',acquisitionType:'grocery',location:'pantry',bestBy:null,acquiredAt:f.lot.acquired_at,acquiredTimePrecision:'exact',note:null});
});

it.each([[8,12,false,4,'original_lot'],[0,12,false,0,'original_lot'],[8,12,true,4,'original_lot'],[null,12,false,6,'product_package_estimate'],[null,0,false,0,'product_package_estimate'],[null,null,false,null,'unavailable']] as const)('allocates lot/package cost without losing unknown, zero or provenance (%s/%s)',async(price,estimate,estimated,value,basis)=>{
 const f=fixture();f.lot.total_cost=price;f.lot.cost_is_estimated=estimated;f.product.estimated_cost=estimate;
 const body=await f.request();expect(validate(body),JSON.stringify(validate.errors)).toBe(true);const v=body.lots[0].valuation;
 expect(v).toMatchObject({originalLotPrice:price,originalLotQuantityBase:907,baseUnit:'g',remainingValue:value,remainingValueBasis:basis,remainingValueIsEstimated:price===null?true:estimated,remainingValueSource:price===null?'Synthetic package estimate':'Synthetic receipt',remainingValuePriceAsOf:price===null?'2026-09-30':'2026-10-01'});
 const app=(await f.app()).inventorySections[0].foods[0];expect(v.remainingValue).toBe(app.cost);expect(v.remainingValueIsEstimated).toBe(app.costIsEstimated);
});

it('makes missing or cross-dimension conversions unavailable, even with density metadata',async()=>{
 const f=fixture('weight','cup',453.592,907,'cup');f.food.g_per_fl_oz=30;
 let row=(await f.request()).lots[0];expect(row.displayQuantity).toBeNull();expect(row.productPackage.displayQuantity).toBeNull();expect(row.baseUnit).toBe('g');
 f.food.display_unit=uuid(999);row=(await f.request()).lots[0];expect(row.displayQuantity).toBeNull();expect(row).not.toHaveProperty('displayUnit');
 f.food.display_unit=unit('oz').id;f.tables.measure_conversions.find(u=>u.short_name==='oz')!.base_to_this_ratio=0;
 expect((await f.request()).lots[0].displayQuantity).toBeNull();
 f.food.measure_style='unsupported';expect((await f.request()).lots[0].baseUnit).toBeNull();
});

it('exposes legacy piece basis without asserting a remaining count and preserves depleted filtering',async()=>{
 const f=fixture();f.lot.piece_count=8;f.lot.piece_basis_qty=907;
 const row=(await f.request()).lots[0];expect(row.pieceBasis).toEqual({pieceCount:8,quantityBase:907,baseUnit:'g',interpretation:'legacy_basis_only',remainingCountConfirmed:false});expect(row.pieceBasis).not.toHaveProperty('remainingPieces');
 f.lot.remaining_qty=0;expect((await f.request()).lots).toHaveLength(0);
 const depleted=await f.request('?includeDepleted=true');expect(validate(depleted),JSON.stringify(validate.errors)).toBe(true);expect(depleted.lots[0]).toMatchObject({quantityBase:0,displayQuantity:0,status:'depleted',valuation:{remainingValue:0}});
});

it.each([[907,'2 lb'],[453.592,'1 lb'],[481.942,'1 lb 1 oz'],[425.243,'15 oz']])('carries rounded ounces into pounds for %sg',async(grams,label)=>{
 const app=await fixture('weight','oz',Number(grams),907).app();expect(app.inventorySections[0].foods[0].total).toBe(label);
});

it('documents the inventory-specific response and price/unit semantics',()=>{
 expect(schema.paths['/v1/inventory'].get.responses['200'].$ref).toBe('#/components/responses/Inventory');
 expect(schema.components.responses.Inventory.content['application/json'].schema.$ref).toBe('#/components/schemas/InventoryResponse');
 expect(schema.components.schemas.InventoryLot.properties.quantityBase.description).toContain('never displayUnit');
});
