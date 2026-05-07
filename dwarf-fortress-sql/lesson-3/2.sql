--solution
SELECT
    d.dwarf_id,
    d.name,
    d.age,
    d.profession,
    json_build_object(
            'skill_ids', COALESCE((
                                      SELECT json_agg(ds.skill_id)
                                      FROM dwarf_skills AS ds
                                      WHERE ds.dwarf_id = d.dwarf_id
                                  ), '[]'::json),
            'assignments_ids', COALESCE((
                                            SELECT json_agg(df.assignment_id)
                                            FROM dwarf_assignments AS df
                                            WHERE df.dwarf_id = d.dwarf_id
                                        ), '[]'::json),
            'squad_ids', COALESCE((
                                      SELECT json_agg(sm.squad_id)
                                      FROM squad_members AS sm
                                      WHERE sm.dwarf_id = d.dwarf_id
                                  ), '[]'::json),
            'equipment_ids', COALESCE((
                                          SELECT json_agg(de.equipment_id)
                                          FROM dwarf_equipment AS de
                                          WHERE de.dwarf_id = d.dwarf_id
                                      ), '[]'::json)
    ) AS related_entities
FROM Dwarves AS d;

--reference

--reflection