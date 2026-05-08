--solution
SELECT s.squad_id,
       s.name,
       s.formation_type,
       s.leader_id,
       json_build_object(
               'member_ids', COALESCE((SELECT json_agg(sm.dwarf_id)
                                       FROM squad_members AS sm
                                       WHERE sm.squad_id = s.squad_id), '[]' ::json),
               'equipment_ids', COALESCE((SELECT json_agg(seq.equipment_id)
                                          FROM squad_equipment seq
                                          WHERE seq.squad_id = s.squad_id), '[]' ::json),
               'operation_ids', COALESCE((SELECT json_agg(sqo.operation_id)
                                          FROM squad_operations AS sqo
                                          WHERE sqo.squad_id = s.squad_id), '[]' ::json),
               'training_schedule_ids', COALESCE((SELECT json_agg(sqt.schedule_id)
                                                  FROM squad_training AS sqt
                                                  WHERE sqt.squad_id = s.squad_id), '[]' ::json),
               'battle_report_ids', COALESCE((SELECT json_agg(sqb.report_id)
                                              FROM squad_battles AS sqb
                                              WHERE sqb.squad_id = s.squad_id), '[]' ::json)
       ) AS related_entities
FROM military_squads AS s;

--reference
SELECT
    s.squad_id,
    s.name,
    s.formation_type,
    s.leader_id,
    JSON_OBJECT(
            'member_ids', (
        SELECT JSON_ARRAYAGG(sm.dwarf_id)
        FROM squad_members sm
        WHERE sm.squad_id = s.squad_id
    ),
            'equipment_ids', (
                SELECT JSON_ARRAYAGG(se.equipment_id)
                FROM squad_equipment se
                WHERE se.squad_id = s.squad_id
            ),
            'operation_ids', (
                SELECT JSON_ARRAYAGG(so.operation_id)
                FROM squad_operations so
                WHERE so.squad_id = s.squad_id
            ),
            'training_schedule_ids', (
                SELECT JSON_ARRAYAGG(st.schedule_id)
                FROM squad_training st
                WHERE st.squad_id = s.squad_id
            ),
            'battle_report_ids', (
                SELECT JSON_ARRAYAGG(sb.report_id)
                FROM squad_battles sb
                WHERE sb.squad_id = s.squad_id
            )
    ) AS related_entities
FROM
    military_squads s;

--reflection