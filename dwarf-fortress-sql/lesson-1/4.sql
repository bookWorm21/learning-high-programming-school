--solution
select dwarves.dwarf_id, dwarves.name, count(dwarves.dwarf_id) as items_count
from Dwarves as dwarves
         right join items on dwarves.dwarf_id = items.owner_id or items.owner_id is null
group by dwarves.dwarf_id, dwarves.name;

--reference
SELECT
    D.name AS DwarfName,
    D.profession AS Profession,
    COUNT(I.item_id) AS ItemCount
FROM
    Dwarves D
        JOIN
    Items I
    ON
        D.dwarf_id = I.owner_id
GROUP BY
    D.dwarf_id, D.name, D.profession;

--reflection
В этом и следующих заданиях сделал допущение, что общий предмет (без owner_id) считаям при подсчете имеющихся предметов
В остальном решение аналогичное