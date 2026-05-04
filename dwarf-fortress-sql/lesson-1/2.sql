--solution
select dwarves.name, dwarves.age, dwarves.profession
from Dwarves as dwarves
where dwarves.squad_id IS NULL and dwarves.profession = 'miner'

--reference
SELECT
    name,
    age
FROM
    Dwarves
WHERE
    profession = 'miner' AND squad_id IS NULL;

--reflection
Отличие решение с целевым в порядке проверок: думаю логичнее проверять сначала profession, так как в реальности
вероятно будет индекс на этом поле и запрос будет работать быстрее