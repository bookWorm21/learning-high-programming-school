select dwarves.name, dwarves.age, dwarves.profession, squads.name, squads.mission
from Dwarves as dwarves
         left join Squads as squads
                   on dwarves.squad_id = squads.squad_id
where dwarves.squad_id IS NOT NULL