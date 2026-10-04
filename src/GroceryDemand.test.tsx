import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { expect, it, vi } from 'vitest';
import { ShoppingReceiptEditor } from './ShoppingReceiptEditor';
import { App } from './App';
import { PantryDataProvider, previewPantryData } from './pantry-data';
import { loadPantryData } from './lib/pantry-repository';

it('defaults receipt to the required product, keeps preference separate, and records a warned substitution truthfully', async () => {
 const save=vi.fn().mockResolvedValue(undefined); const user=userEvent.setup();
 const data={...previewPantryData,foods:[{id:'food',name:'Yogurt',emoji:'',measureStyle:'discrete' as const}],units:[{id:'ct',shortName:'ct',label:'count',measureStyle:'discrete' as const}],products:['required','preferred'].map(id=>({...previewPantryData.products[0],id,foodId:'food',label:id}))};
 render(<PantryDataProvider data={data}><ShoppingReceiptEditor item={{id:'row',name:'Yogurt',quantity:'3 ct',quantityNeeded:3,foodId:'food',unitId:'ct',requiredProductId:'required',requiredProductName:'Required yogurt',pinnedProductId:'preferred'}} onSave={save} onClose={()=>{}} /></PantryDataProvider>);
 expect(screen.getByLabelText('Product')).toHaveValue('required');
 await user.selectOptions(screen.getByLabelText('Product'),'preferred');
 expect(screen.getByRole('status')).toHaveTextContent('Plan still needs Required yogurt.');
 await user.click(screen.getByRole('button',{name:'Add to inventory'}));
 await waitFor(()=>expect(save).toHaveBeenCalledWith('row',expect.objectContaining({productId:'preferred',quantity:3})));
});

it('shows scoped grocery identity and cumulative exact-lot shortage from actual repository data', async () => {
 const date=new Intl.DateTimeFormat('en-CA',{timeZone:'UTC',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const tables: Record<string, any[]>={
  personal_settings:[{time_zone:'UTC'}],measure_conversions:[{id:'ct',short_name:'ct',measure_style:'discrete',base_to_this_ratio:1}],
  base_foods:[{id:'food',name:'Yogurt',measure_style:'discrete',display_unit:'ct'}],
  products:['required','preferred'].map(id=>({id,food:'food',name:id,package_qty_base:1,package_unit:'ct',serving_qty_base:1,nutrition_basis_qty:1,estimated_cost:id==='required'?2:1,archived_at:null})),
  inventory_lots:[{id:'lot',product:'required',initial_qty:2,remaining_qty:2,acquired_at:date+'T12:00:00Z',location:'fridge'}],
  shopping_items:[{id:'scoped',food:'food',generated_product:'required',pinned_product:'preferred',source:'generated',generated_active:true,qty_needed:3,quantity_label:null,unit:'ct',received_qty_base:0,generated_shortage_base:3}],
  meal_plans:[1,2,3].map(i=>({id:String(i),inventory_lot:'lot',intent:'consume',consume_from_inventory:true,plan_date:date,daypart:'lunch',status:'planned',group_id:String(i)})),
  planned_consumptions:[1,2,3].map(i=>({meal_plan:String(i),servings:1,status:'planned'})),
 };
 const db={from(table:string){let data:any=tables[table]??[];const query:any=new Proxy({}, {get(_t,key){if(key==='then')return (yes:any,no:any)=>Promise.resolve({data,error:null}).then(yes,no);return ()=>{if(key==='single')data=data[0];return query;};}});return query;}};
 const data=await loadPantryData(db as Parameters<typeof loadPantryData>[0]);
 expect(data.grocerySections.flatMap(s=>s.items)[0]).toMatchObject({id:'scoped',name:'required',requiredProductId:'required',pinnedProductId:'preferred',quantityNeeded:3,cost:6});
 expect(data.plannedMeals).toHaveLength(3);
 expect(data.plannedMeals.every(p=>p.sourceServingsAvailable===2 && p.sourceShortfall)).toBe(true);
 const consume=vi.fn();render(<PantryDataProvider data={data}><App onConsumePlannedMeals={consume} /></PantryDataProvider>);
 await userEvent.click(screen.getByRole('button',{name:/This week/}));
 expect(screen.getAllByText('Check source')).toHaveLength(3);
 expect(screen.getAllByText('Stock short · adjust portion')).toHaveLength(3);
 expect(screen.getAllByRole('button',{name:/Remove required/})).toHaveLength(3);
});
