with grammar(legacy_firebase_id, name, plural) as (
  values
    ('pork-loin', 'Boneless pork loin', 'Boneless pork loins'),
    ('signature-chicken-thighs', 'Boneless skinless chicken thigh', 'Boneless skinless chicken thighs'),
    ('mission-burrito-tortillas', 'Burrito-size flour tortilla', 'Burrito-size flour tortillas'),
    ('carrots', 'Carrot', 'Carrots'),
    ('external:chick-fil-a-chicken-biscuit', 'Chicken Biscuit', 'Chicken Biscuits'),
    ('egg', 'Egg', 'Eggs'),
    ('bubba-burger', 'Frozen beef burger patty', 'Frozen beef burger patties'),
    ('tyson-chicken-twists', 'Frozen breaded chicken twist', 'Frozen breaded chicken twists'),
    ('burger-bun', 'Hamburger bun', 'Hamburger buns'),
    ('hillshire-honey-ham', 'Honey ham slice', 'Honey ham slices'),
    ('sargento-medium-cheddar', 'Medium cheddar slice', 'Medium cheddar slices'),
    ('ny-strip-steak', 'New York strip steak', 'New York strip steaks'),
    ('onion', 'Onion', 'Onions'),
    ('pepperidge-plain-bagels', 'Plain bagel', 'Plain bagels'),
    ('pork-tenderloin', 'Pork tenderloin', 'Pork tenderloins'),
    ('ritz-crackers', 'Round butter cracker', 'Round butter crackers'),
    ('russet-potatoes', 'Russet potato', 'Russet potatoes'),
    ('semisweet-chocolate-chips', 'Semisweet chocolate chip', 'Semisweet chocolate chips'),
    ('unidentified-steak', 'Unidentified steak (identify/weigh later)', 'Unidentified steaks (identify/weigh later)')
)
update public.base_foods as food
set name = grammar.name,
    plural = grammar.plural
from grammar
where food.legacy_firebase_id = grammar.legacy_firebase_id
  and (food.name, food.plural) is distinct from (grammar.name, grammar.plural);
