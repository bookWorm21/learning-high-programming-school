--solution
select
    d.dwarf_id as DwarveID,
    d.name as DwarveName,
    count(i.type) as WeaponsCount
from
    dwarves as d
        inner join
    Items as i
    on d.dwarf_id = i.owner_id
where i.type = 'Weapon'
group by (d.dwarf_id, d.name);

--reference
SELECT DISTINCT D.*
FROM Dwarves D
         JOIN Items I ON D.dwarf_id = I.owner_id
WHERE I.type = 'weapon';

--reflection
В референсном решении уникальность айди дварфов достигается с помощью select distinct, я реализовал это через group by,
так как добавил в вывод количество weapon предметов. select distinct должен работать быстрее