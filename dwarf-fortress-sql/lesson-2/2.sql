--solution
select
    d.dwarf_id as DwarveID,
    d.name as DwarveName,
    d.age as DwarveAge,
    d.profession as DwarveProfession
from Dwarves as d
where d.profession = 'Warrior' and d.age > 150;

--reference
SELECT *
FROM Dwarves
WHERE age > 150 AND profession = 'Warrior';

--reflection
Проверяю сначала profession, из предположений по поводу индекса по аналогии из предыдущего задания