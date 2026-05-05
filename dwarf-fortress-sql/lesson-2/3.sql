--solution
select
    d.dwarf_id as DwarveID,
    d.name as DwarveName,
    count(i.type) as WeaponsCount
from
    dwarves as d
        inner join
    Items as i
    on d.dwarf_id = i.owner_id
where i.type = 'Weapon'
group by (d.dwarf_id, d.name);

--reference

--reflection