select dwarves.name, dwarves.age, dwarves.profession
from Dwarves as dwarves
where dwarves.squad_id IS NULL and dwarves.profession = 'miner'