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

--reflection