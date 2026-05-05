--solution
select
    d.dwarf_id as DwarveID,
    d.name as DwarveName,
    t.status as TaskStatus,
    count(t.task_id) as TaskCount
from
    Dwarves as d
        inner join
    Tasks as t
    on d.dwarf_id = t.assigned_to
group by (d.dwarf_id, d.name, t.status)

--reference
SELECT assigned_to, status, COUNT(*) AS task_count
FROM Tasks
GROUP BY assigned_to, status;

--reflection
Сделал лишний join с таблицей дварфов, хотя в таблице tasks информации хватает: плохой инстинкт делать join для добычи информации, буду стараться минимизировать количество таблица в запросе