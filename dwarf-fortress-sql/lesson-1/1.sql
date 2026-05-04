--solution
select dwarves.name, dwarves.age, dwarves.profession, squads.name, squads.mission
from Dwarves as dwarves
         left join Squads as squads
                   on dwarves.squad_id = squads.squad_id
where dwarves.squad_id IS NOT NULL

--reference
SELECT
    D.name AS DwarfName,
    D.profession AS Profession,
    S.name AS SquadName,
    S.mission AS Mission
FROM
    Dwarves D
        JOIN
    Squads S
    ON
        D.squad_id = S.squad_id;

--reflection
1. Из-за left join добавилась проверка на не пустой squad_id, с inner join запрос проще
2. Не указал алиасы для полей в select, что уходшает вывод, так как зависит от нейминга полей в самой таблице