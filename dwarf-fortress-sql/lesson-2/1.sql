--solution
select
    s.squad_id as SquadID,
    s.name as SquadName
from Squads as s
where s.leader_id is null;

--reference

--reflection