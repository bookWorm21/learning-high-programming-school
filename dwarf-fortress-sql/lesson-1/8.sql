--solution
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

--reference
SELECT
    D.name,
    D.age,
    D.profession
FROM
    Dwarves D
WHERE
    D.age > (SELECT AVG(age) FROM Dwarves)
  AND D.dwarf_id NOT IN (SELECT owner_id FROM Items);

--reflection
Аналогичное решение, но запрос для поиска дварфа без предмета сложнее из-за допущения, что общий предмет идет в счет каждого гнома