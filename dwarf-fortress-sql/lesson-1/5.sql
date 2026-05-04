--solution
select squads.squad_id, squads.name, count(squads.squad_id)
from Squads as squads
         right join Dwarves as dwarves on squads.squad_id = dwarves.squad_id
where dwarves.squad_id is not null
group by squads.squad_id, squads.name
union
select squads.squad_id, squads.name, 0
from Squads as squads
where not exists (
    select 1
    from Dwarves as dwarves
    where squads.squad_id = dwarves.squad_id
);

--reference
SELECT
    S.squad_id,
    S.name AS SquadName,
    COUNT(D.dwarf_id) AS NumberOfDwarves
FROM
    Squads S
        LEFT JOIN
    Dwarves D
    ON
        S.squad_id = D.squad_id
GROUP BY
    S.squad_id, S.name;

--reflection
Костыль с "not exists" решал проблему, что в пустом отрядке после группировки у меня получалось 1, а не 0
Нужно было группировать по нужному полю, которое может быть null, тогда рассчет корректный