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
