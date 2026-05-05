--solution
select
    d.name as DwarveName,
    r.relationship as Relationship,
    dr.name as DwarveRelation
from
    Dwarves as d
        left join
    Relationships as r
    on d.dwarf_id = r.dwarf_id
        left join
    Dwarves as dr
    on r.related_to = dr.dwarf_id;

--reference

--reflection