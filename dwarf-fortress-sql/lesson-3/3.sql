--solution
SELECT ws.workshop_id,
       ws.name,
       ws.type,
       ws.quality,
       json_build_object(
               'craftsdwarf_ids', COALESCE((SELECT json_agg(wscd.dwarf_id)
                                            FROM workshop_craftsdwarves AS wscd
                                            WHERE wscd.workshop_id = ws.workshop_id), '[]' ::json),
               'project_ids', COALESCE((SELECT json_agg(p.project_id)
                                        FROM projects AS p
                                        WHERE p.workshop_id = ws.workshop_id), '[]' ::json),
               'input_material_ids', COALESCE((SELECT json_agg(wm.material_id)
                                               FROM workshop_materials AS wm
                                               WHERE wm.workshop_id = ws.workshop_id), '[]' ::json),
               'output_product_ids', COALESCE((SELECT json_agg(wd.product_id)
                                               FROM workshop_products AS wd
                                               WHERE wd.workshop_id = ws.workshop_id), '[]' ::json)
       ) AS related_entities
FROM workshops AS ws;

--reference
SELECT
    w.workshop_id,
    w.name,
    w.type,
    w.quality,
    JSON_OBJECT(
            'craftsdwarf_ids', (
        SELECT JSON_ARRAYAGG(wc.dwarf_id)
        FROM workshop_craftsdwarves wc
        WHERE wc.workshop_id = w.workshop_id
    ),
            'project_ids', (
                SELECT JSON_ARRAYAGG(p.project_id)
                FROM projects p
                WHERE p.workshop_id = w.workshop_id
            ),
            'input_material_ids', (
                SELECT JSON_ARRAYAGG(wm.material_id)
                FROM workshop_materials wm
                WHERE wm.workshop_id = w.workshop_id AND wm.is_input = TRUE
            ),
            'output_product_ids', (
                SELECT JSON_ARRAYAGG(wp.product_id)
                FROM workshop_products wp
                WHERE wp.workshop_id = w.workshop_id
            )
    ) AS related_entities
FROM
    workshops w;

--reflection