--solution
select items.type, avg(dwarves.age)
from Items as items
         left join Dwarves as dwarves on items.owner_id = dwarves.dwarf_id or items.owner_id is null
group by items.type;

--reference
SELECT
    I.type AS ItemType,
    AVG(D.age) AS AverageAge
FROM
    Items I
        JOIN
    Dwarves D
    ON
        I.owner_id = D.dwarf_id
GROUP BY
    I.type;

--reflection
Решение аналогичное, но в моем допущении, что общий предмет идет в счет каждого гнома