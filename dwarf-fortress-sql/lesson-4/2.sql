--solution
WITH
-- Просчёт простоя мастерской:
-- простой мастерской = ни один дварф не имел назначений в это время в мастерской.
-- Так как в мастерской может работать больше одного дварфа,
-- нужно осуществить мердж интервалов занятости всех работающих дварфов.
--
-- 1. workshop_assignments_with_end_date
-- устанавливаем в end_date (временной таблицы) текущее время для незаконченных назначений
-- 2. ordered_assignments
-- с помощью оконной функции создаем поле previous_max_end_date, в котором храним предыдущий максимум
-- по правой границе интервала, сравниваем соседей (ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
-- 3. marked_groups
-- создаем is_new_period, которая означает начало нового периода для склейки, так как границы не пересекаются
-- 4. grouped_periods
-- на основе is_new_period проставляем period_number, как сумма предыдущих строк по флагу
-- 5. merged_periods
-- по period_number соединяем интервалы
-- 6. merged_periods_with_prev_right_border
-- чтобы подсчитать простой нужно знать время окончания левой границы, для этого подсчитываем prev_right_border
-- 7. workshop_idles
-- суммируем простои как сумму (start_date - prev_right_border)
--
workshop_assignments_with_end_date AS (
    SELECT
        wcr.workshop_id,
        dwa.start_date,
        dwa.assignment_id,
        COALESCE(dwa.end_date, CURRENT_DATE) AS end_date
    FROM workshop_craftsdwarves AS wcr
             LEFT JOIN dwarf_assignments AS dwa
                       ON wcr.dwarf_id = dwa.dwarf_id
),

ordered_assignments AS (
    SELECT
        wa.workshop_id,
        wa.start_date,
        wa.end_date,
        wa.assignment_id,
        MAX(wa.end_date) OVER (
            PARTITION BY wa.workshop_id
            ORDER BY wa.start_date, wa.end_date, wa.assignment_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS previous_max_end_date
    FROM workshop_assignments_with_end_date AS wa
),

marked_groups AS (
    SELECT
        oa.workshop_id,
        oa.start_date,
        oa.end_date,
        oa.assignment_id,
        CASE
            WHEN oa.previous_max_end_date IS NULL THEN 1
            WHEN oa.start_date > oa.previous_max_end_date THEN 1
            ELSE 0
            END AS is_new_period
    FROM ordered_assignments AS oa
),

grouped_periods AS (
    SELECT
        mg.workshop_id,
        mg.start_date,
        mg.end_date,
        SUM(mg.is_new_period) OVER (
            PARTITION BY mg.workshop_id
            ORDER BY mg.start_date, mg.end_date, mg.assignment_id
            ) AS period_number
    FROM marked_groups AS mg
),

merged_periods AS (
    SELECT
        gp.workshop_id,
        MIN(gp.start_date) AS left_border,
        MAX(gp.end_date) AS right_border
    FROM grouped_periods AS gp
    GROUP BY
        gp.workshop_id,
        gp.period_number
),

merged_periods_with_prev_right_border AS (
    SELECT
        mp.workshop_id,
        mp.left_border,
        mp.right_border,
        LAG(mp.right_border) OVER (
            PARTITION BY mp.workshop_id
            ORDER BY mp.left_border
            ) AS prev_right_border
    FROM merged_periods AS mp
),

workshop_idles AS (
    SELECT
        mprb.workshop_id,
        SUM(
                CASE
                    WHEN mprb.prev_right_border IS NULL THEN 0
                    ELSE mprb.left_border - mprb.prev_right_border
                    END
        ) AS idle_time
    FROM merged_periods_with_prev_right_border AS mprb
    GROUP BY
        mprb.workshop_id
),

workshop_timing AS (
    SELECT
        wcr.workshop_id,
        SUM(dwa.end_date - dwa.start_date) AS sum_work_days_count
    FROM workshop_craftsdwarves AS wcr
             LEFT JOIN dwarf_assignments AS dwa
                       ON wcr.dwarf_id = dwa.dwarf_id
    GROUP BY
        wcr.workshop_id
),

workshop_products_stats AS (
    SELECT
        w.workshop_id,
        w.name,
        w.type,
        SUM(wp.quantity) AS total_quantity_produced,
        SUM(wp.quantity * p.value) AS total_production_value,
        SUM(wp.quantity * p.value * p.quality) AS total_production_quality_myl_value,
        SUM(wm.quantity) AS total_quantity_material_used,
        (MAX(wp.production_date) - MIN(wp.production_date)) + 1 AS work_days
    FROM workshops AS w
             LEFT JOIN products AS p
                       ON w.workshop_id = p.workshop_id
             LEFT JOIN workshop_products AS wp
                       ON w.workshop_id = wp.workshop_id
                           AND p.product_id = wp.product_id
             LEFT JOIN workshop_materials AS wm
                       ON w.workshop_id = wm.workshop_id
                           AND wm.is_input
    GROUP BY
        w.workshop_id,
        w.name,
        w.type
),

workshops_craftsdwarves_stats AS (
    SELECT
        wcr.workshop_id,
        COUNT(DISTINCT (dws.dwarf_id, dws.skill_id)) AS num_craftsdwarves,
        SUM(dws.skill_id) AS sum_crafts_dwarves_skills
    FROM workshop_craftsdwarves AS wcr
             LEFT JOIN dwarf_skills AS dws
                       ON wcr.dwarf_id = dws.dwarf_id
    GROUP BY
        wcr.workshop_id
),

workshop_correlations AS (
    SELECT
        wps.workshop_id,
        COALESCE(
                ROUND(
                        wps.total_production_quality_myl_value::NUMERIC
                            / NULLIF(wps.total_production_value, 0),
                        2
                ),
                0
        ) AS value_per_material_unit,
        COALESCE(
                ROUND(
                        wcs.sum_crafts_dwarves_skills::NUMERIC
                            / NULLIF(wcs.num_craftsdwarves, 0),
                        2
                ),
                0
        ) AS average_craftsdwarf_skill
    FROM workshop_products_stats AS wps
             LEFT JOIN workshops_craftsdwarves_stats AS wcs
                       ON wps.workshop_id = wcs.workshop_id
)

SELECT
    wps.workshop_id,
    wps.name,
    wps.type,

    COALESCE(wcs.num_craftsdwarves, 0) AS num_craftsdwarves,
    COALESCE(wps.total_quantity_produced, 0) AS total_quantity_produced,
    COALESCE(wps.total_production_value, 0) AS total_production_value,

    COALESCE(
            ROUND(
                    wps.total_production_value::NUMERIC
                        / NULLIF(wps.work_days, 0),
                    2
            ),
            0
    ) AS daily_production_rate,

    COALESCE(
            ROUND(
                    wps.total_production_value::NUMERIC
                        / NULLIF(wt.sum_work_days_count, 0),
                    2
            ),
            0
    ) AS craft_dwarves_perfomance,

    wcorr.value_per_material_unit,

    COALESCE(
            ROUND(
                    wi.idle_time::NUMERIC
                        / NULLIF(wt.sum_work_days_count, 0),
                    2
            ) * 100,
            0
    ) AS workshop_utilization_percent,

    COALESCE(
            ROUND(
                    wps.total_quantity_produced::NUMERIC
                        / NULLIF(wps.total_quantity_material_used, 0),
                    2
            ),
            0
    ) AS material_conversion_ratio,

    wcorr.average_craftsdwarf_skill,

    COALESCE(
            ROUND(
                    wcorr.average_craftsdwarf_skill::NUMERIC
                        / NULLIF(wcorr.value_per_material_unit, 0),
                    2
            ),
            0
    ) AS skill_quality_correlation,

    JSON_BUILD_OBJECT(
            'craftsdwarf_ids',
            COALESCE(
                    (
                        SELECT JSON_AGG(wcr.dwarf_id)
                        FROM workshop_craftsdwarves AS wcr
                        WHERE wcr.workshop_id = wps.workshop_id
                    ),
                    '[]'::JSON
            ),

            'product_ids',
            COALESCE(
                    (
                        SELECT JSON_AGG(wp.product_id)
                        FROM workshop_products AS wp
                        WHERE wp.workshop_id = wps.workshop_id
                    ),
                    '[]'::JSON
            ),

            'material_ids',
            COALESCE(
                    (
                        SELECT JSON_AGG(wm.material_id)
                        FROM workshop_materials AS wm
                        WHERE wm.workshop_id = wps.workshop_id
                    ),
                    '[]'::JSON
            ),

            'project_ids',
            COALESCE(
                    (
                        SELECT JSON_AGG(p.project_id)
                        FROM projects AS p
                        WHERE p.workshop_id = wps.workshop_id
                    ),
                    '[]'::JSON
            )
    ) AS related_entities

FROM workshop_products_stats AS wps
         LEFT JOIN workshops_craftsdwarves_stats AS wcs
                   ON wps.workshop_id = wcs.workshop_id
         LEFT JOIN workshop_correlations AS wcorr
                   ON wps.workshop_id = wcorr.workshop_id
         LEFT JOIN workshop_timing AS wt
                   ON wps.workshop_id = wt.workshop_id
         LEFT JOIN workshop_idles AS wi
                   ON wps.workshop_id = wi.workshop_id;