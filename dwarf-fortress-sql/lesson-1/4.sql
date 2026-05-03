select dwarves.dwarf_id, dwarves.name, count(dwarves.dwarf_id) as items_count
from Dwarves as dwarves
         right join items on dwarves.dwarf_id = items.owner_id or items.owner_id is null
group by dwarves.dwarf_id, dwarves.name;