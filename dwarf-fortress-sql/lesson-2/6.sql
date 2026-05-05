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
SELECT D1.name AS dwarf_name, D2.name AS relative_name, R.relationship
FROM Relationships R
         JOIN Dwarves D1 ON R.dwarf_id = D1.dwarf_id
         JOIN Dwarves D2 ON R.related_to = D2.dwarf_id;

--reflection
Аналогичное решение через join таблицы дварфов с самой собой через таблицу связей