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

--reflection