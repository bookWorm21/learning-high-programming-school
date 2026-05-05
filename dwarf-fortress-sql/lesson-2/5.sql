--solution
select
    t.task_id as TaskID,
    t.description as TaskDescription
from
    Tasks as t
        inner join
    Dwarves as d
    on t.assigned_to = d.dwarf_id
        inner join
    Squads as s
    on d.squad_id = s.squad_id
where s.name = 'Guardians'


--reference
SELECT T.*
FROM Tasks T
         JOIN Dwarves D ON T.assigned_to = D.dwarf_id
         JOIN Squads S ON D.squad_id = S.squad_id
WHERE S.name = 'Guardians';

--reflection
Аналогичное решение через два join