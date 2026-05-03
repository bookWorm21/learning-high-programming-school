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
