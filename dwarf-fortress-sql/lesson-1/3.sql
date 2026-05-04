--solution
select tasks.description
from Tasks as tasks
where priority = 1 and status = 'pending'

--reference
SELECT
    task_id,
    description,
    assigned_to
FROM
    Tasks
WHERE
    priority = (SELECT MAX(priority) FROM Tasks WHERE status = 'pending')
  AND status = 'pending';

--reflection
Не правильно понял условия и воспринял "максимальный приоритет" как константу, а не значение которое нужно находить
в остальном запрос корректный