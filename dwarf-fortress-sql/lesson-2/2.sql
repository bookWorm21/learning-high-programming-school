--solution
select
    d.dwarf_id as DwarveID,
    d.name as DwarveName,
    d.age as DwarveAge,
    d.profession as DwarveProfession
from Dwarves as d
where d.profession = 'Warrior' and d.age > 150;

--reference

--reflection