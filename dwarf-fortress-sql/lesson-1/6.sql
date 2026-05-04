--solution
with professitions_tasks as
         (select dwarves.profession, count(dwarves.profession) as not_completed_tasks
          from Dwarves as dwarves
                   left join Tasks as tasks on dwarves.dwarf_id = tasks.assigned_to
          where status in ('pending', 'in_progress')
          group by dwarves.profession)

select professitions_tasks.profession, professitions_tasks.not_completed_tasks
from professitions_tasks
where professitions_tasks.not_completed_tasks =
      (select max(professitions_tasks.not_completed_tasks) from professitions_tasks);

--reference
SELECT
    D.profession,
    COUNT(T.task_id) AS UnfinishedTasksCount
FROM
    Dwarves D
        JOIN
    Tasks T
    ON
        D.dwarf_id = T.assigned_to
WHERE
    T.status IN ('pending', 'in_progress')
GROUP BY
    D.profession
ORDER BY
    UnfinishedTasksCount DESC;

--reflection
Воспринял условие, что нужно вывести все профессии, у которых значениях равно максимуму, в референсном решении же отсортированный вывод по значению
Сделал left join, чтобы охватить кейсы, когда у профессии 0 тасок подходящих под условия, в референсном решении вывода таких профессий не будет