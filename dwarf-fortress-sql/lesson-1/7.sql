select items.type, avg(dwarves.age)
from Items as items
         left join Dwarves as dwarves on items.owner_id = dwarves.dwarf_id or items.owner_id is null
group by items.type;