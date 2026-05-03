with dwarves_with_items as
         (
             select dwarves.dwarf_id
             from Dwarves as dwarves
                      right join items on dwarves.dwarf_id = items.owner_id or items.owner_id is null
             group by dwarves.dwarf_id
         )

select dwarves.name
from Dwarves as dwarves
where
    dwarves.dwarf_id not in (
        select dwarves_with_items.dwarf_id
        from dwarves_with_items
    ) and
    dwarves.age > (
        select avg(dwarves.age) from Dwarves as dwarves
    );
