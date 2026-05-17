--solution

-- casualty_rate - как часто в битвах случаются потери
-- casualty_exchange_ratio - сравнение с потерями врага

WITH
    battles_stats AS (
        SELECT
            sb.squad_id,
            COUNT(sb.report_id) AS total_battles,
            COUNT(sb.report_id) FILTER (
            WHERE sb.outcome = 'victory'
        ) AS victories,
            COUNT(sb.report_id) FILTER (
            WHERE sb.casualties > 0
        ) AS battles_with_casualties_count,
            SUM(sb.casualties) AS total_casualties,
            SUM(sb.enemy_casualties) AS total_enemy_casualties

        -- victory_percentage:
        -- victories / total_battles * 100
        --
        -- casualty_rate:
        -- battles_with_casualties_count / total_battles * 100
        --
        -- casualty_exchange_ratio:
        -- total_casualties / total_enemy_casualties
        FROM squad_battles AS sb
        GROUP BY
            sb.squad_id
    ),

    squad_dwarfs_stats AS (
        SELECT
            sm.squad_id,
            COUNT(ds.skill_id) AS total_skill_improvement
        FROM squad_members AS sm
                 LEFT JOIN dwarf_skills AS ds
                           ON sm.dwarf_id = ds.dwarf_id
                               AND ds.date BETWEEN sm.join_date AND sm.exit_date
        GROUP BY
            sm.squad_id
    ),

    squad_training_with_prev_training_date AS (
        SELECT
            st.squad_id,
            st.effectiveness,
            st.schedule_id,
            st.date,
            LAG(st.date) OVER (
            PARTITION BY st.squad_id
            ORDER BY st.date
        ) AS prev_training_date
        FROM squad_training AS st
    ),

    first_training AS (
        SELECT
            st.squad_id,
            MIN(st.date) AS first_training_date
        FROM squad_training AS st
        GROUP BY
            st.squad_id
    ),

    stats_before_training AS (
        SELECT
            ft.squad_id,
            COUNT(sb.report_id) AS total_battles,
            COUNT(sb.report_id) FILTER (
            WHERE sb.outcome = 'victory'
        ) AS victories,
            COUNT(sb.report_id) FILTER (
            WHERE sb.casualties > 0
        ) AS battles_with_casualties_count,
            COALESCE(SUM(sb.casualties), 0) AS total_casualties,
            COALESCE(SUM(sb.enemy_casualties), 0) AS total_enemy_casualties
        FROM first_training AS ft
                 LEFT JOIN squad_battles AS sb
                           ON sb.squad_id = ft.squad_id
                               AND sb.date < ft.first_training_date
        GROUP BY
            ft.squad_id
    ),

    training_stats AS (
        SELECT
            stw.squad_id,
            COUNT(stw.schedule_id) AS total_training_sessions,
            AVG(stw.effectiveness) AS avg_training_effectiveness,
            COUNT(sb.report_id) AS total_battles,
            COUNT(sb.report_id) FILTER (
            WHERE sb.outcome = 'victory'
        ) AS victories,
            COUNT(sb.report_id) FILTER (
            WHERE sb.casualties > 0
        ) AS battles_with_casualties_count,
            COALESCE(SUM(sb.casualties), 0) AS total_casualties,
            COALESCE(SUM(sb.enemy_casualties), 0) AS total_enemy_casualties
        FROM squad_training_with_prev_training_date AS stw
                 LEFT JOIN squad_battles AS sb
                           ON sb.squad_id = stw.squad_id
                               AND (
                                  (
                                      stw.prev_training_date IS NULL
                                          AND sb.date < stw.date
                                      )
                                      OR (
                                      stw.prev_training_date IS NOT NULL
                                          AND sb.date BETWEEN stw.prev_training_date AND stw.date
                                      )
                                  )
        GROUP BY
            stw.squad_id
    ),

    training_metrics AS (
        SELECT
            ts.squad_id,
            ts.total_battles,
            ts.victories,
            ts.battles_with_casualties_count,
            ts.total_casualties,
            ts.total_enemy_casualties,

            COALESCE(
                    ROUND(
                            ts.victories::NUMERIC
                / NULLIF(ts.total_battles, 0),
                            2
                    ),
                    0
            ) AS winrate,

            COALESCE(
                    ROUND(
                            ts.battles_with_casualties_count::NUMERIC
                / NULLIF(ts.total_battles, 0),
                            2
                    ),
                    0
            ) AS casualty_rate,

            COALESCE(
                    ROUND(
                            ts.total_casualties::NUMERIC
                / NULLIF(ts.total_enemy_casualties, 0),
                            2
                    ),
                    0
            ) AS casualty_exchange_ratio
        FROM training_stats AS ts
    ),

    stats_before_training_metrics AS (
        SELECT
            sbt.squad_id,

            COALESCE(
                    ROUND(
                            sbt.victories::NUMERIC
                / NULLIF(sbt.total_battles, 0),
                            2
                    ),
                    0
            ) AS winrate,

            COALESCE(
                    ROUND(
                            sbt.battles_with_casualties_count::NUMERIC
                / NULLIF(sbt.total_battles, 0),
                            2
                    ),
                    0
            ) AS casualty_rate,

            COALESCE(
                    ROUND(
                            sbt.total_casualties::NUMERIC
                / NULLIF(sbt.total_enemy_casualties, 0),
                            2
                    ),
                    0
            ) AS casualty_exchange_ratio
        FROM stats_before_training AS sbt
    ),

    training_metrics_with_prev AS (
        SELECT
            tm.*,

            COALESCE(
                    LAG(tm.winrate) OVER (
                    PARTITION BY tm.squad_id
                                    ),
                    sbtm.winrate
            ) AS prev_winrate,

            COALESCE(
                    LAG(tm.casualty_rate) OVER (
                    PARTITION BY tm.squad_id
                                          ),
                    sbtm.casualty_rate
            ) AS prev_casualty_rate,

            COALESCE(
                    LAG(tm.casualty_exchange_ratio) OVER (
                    PARTITION BY tm.squad_id
                                                    ),
                    sbtm.casualty_exchange_ratio
            ) AS prev_casualty_exchange_ratio
        FROM training_metrics AS tm
                 LEFT JOIN stats_before_training_metrics AS sbtm
                           ON sbtm.squad_id = tm.squad_id
    ),

    training_correlation AS (
        SELECT
            tmwp.squad_id,

            COALESCE(
                    ROUND(
                            (tmwp.winrate - tmwp.prev_winrate)
                                / NULLIF(tmwp.prev_winrate, 0),
                            2
                    ),
                    CASE
                        WHEN tmwp.winrate > 0 THEN 1
                        ELSE 0
                        END
            ) AS winrate_diff,

            COALESCE(
                    ROUND(
                            (tmwp.casualty_rate - tmwp.prev_casualty_rate)
                                / NULLIF(tmwp.prev_casualty_rate, 0),
                            2
                    ),
                    CASE
                        WHEN tmwp.casualty_rate > 0 THEN 1
                        ELSE 0
                        END
            ) AS casualty_rate_diff,

            COALESCE(
                    ROUND(
                            (
                                tmwp.casualty_exchange_ratio
                                    - tmwp.prev_casualty_exchange_ratio
                                )
                                / NULLIF(tmwp.prev_casualty_exchange_ratio, 0),
                            2
                    ),
                    CASE
                        WHEN tmwp.casualty_exchange_ratio > 0 THEN 1
                        ELSE 0
                        END
            ) AS casualty_exchange_ratio_diff
        FROM training_metrics_with_prev AS tmwp
    ),

    equipment_stats AS (
        SELECT
            se.squad_id,
            AVG(se.quantity) AS avg_equipment_quality
        FROM squad_equipment AS se
        GROUP BY
            se.squad_id
    ),

    membership AS (
        SELECT
            sm.squad_id,
            COUNT(sm.dwarf_id) FILTER (
            WHERE sm.exit_date IS NULL
        ) AS current_members,
            COUNT(sm.dwarf_id) AS total_members_ever

        -- retention_rate:
        -- current_members / total_members_ever * 100
        FROM squad_members AS sm
        GROUP BY
            sm.squad_id
    ),

    squad_effective AS (
        SELECT
            ms.squad_id,
            ms.name AS squad_name,
            ms.formation_type,
            leaders_dw.name AS leader_name,

            bs.total_battles,
            bs.victories,

            COALESCE(
                    ROUND(
                            bs.victories::NUMERIC
                / NULLIF(bs.total_battles, 0),
                            2
                    ) * 100,
                    0
            ) AS victory_percentage,

            COALESCE(
                    ROUND(
                            bs.battles_with_casualties_count::NUMERIC
                / NULLIF(bs.total_battles, 0),
                            2
                    ),
                    0
            ) AS casualty_rate,

            COALESCE(
                    ROUND(
                            bs.total_casualties::NUMERIC
                / NULLIF(bs.total_enemy_casualties, 0),
                            2
                    ),
                    0
            ) AS casualty_exchange_ratio,

            memb.current_members,
            memb.total_members_ever,

            COALESCE(
                    ROUND(
                            memb.current_members::NUMERIC
                / NULLIF(memb.total_members_ever, 0),
                            2
                    ) * 100,
                    0
            ) AS retention_rate,

            eqs.avg_equipment_quality,

            ts.total_training_sessions,
            ts.avg_training_effectiveness,

            COALESCE(
                    ROUND(
                            (
                                tr_corr.winrate_diff::NUMERIC
                    + tr_corr.casualty_rate_diff
                    + tr_corr.casualty_exchange_ratio_diff
                                ) / 3,
                            2
                    ),
                    0
            ) AS training_battle_correlation,

            COALESCE(
                    ROUND(
                            sds.total_skill_improvement::NUMERIC
                / NULLIF(memb.total_members_ever, 0),
                            2
                    ),
                    0
            ) AS avg_combat_skill_improvement,

            JSON_BUILD_OBJECT(
                    'member_ids',
                    COALESCE(
                            (
                                SELECT JSON_AGG(sm.dwarf_id)
                                FROM squad_members AS sm
                                WHERE ms.squad_id = sm.squad_id
                            ),
                            '[]'::JSON
                    ),

                    'equipment_ids',
                    COALESCE(
                            (
                                SELECT JSON_AGG(se.equipment_id)
                                FROM squad_equipment AS se
                                WHERE ms.squad_id = se.squad_id
                            ),
                            '[]'::JSON
                    ),

                    'battle_report_ids',
                    COALESCE(
                            (
                                SELECT JSON_AGG(sb.report_id)
                                FROM squad_battles AS sb
                                WHERE ms.squad_id = sb.squad_id
                            ),
                            '[]'::JSON
                    ),

                    'training_ids',
                    COALESCE(
                            (
                                SELECT JSON_AGG(st.schedule_id)
                                FROM squad_training AS st
                                WHERE ms.squad_id = st.squad_id
                            ),
                            '[]'::JSON
                    )
            ) AS related_entities

        FROM military_squads AS ms
                 LEFT JOIN dwarves AS leaders_dw
                           ON ms.leader_id = leaders_dw.dwarf_id
                 LEFT JOIN battles_stats AS bs
                           ON ms.squad_id = bs.squad_id
                 LEFT JOIN membership AS memb
                           ON ms.squad_id = memb.squad_id
                 LEFT JOIN equipment_stats AS eqs
                           ON ms.squad_id = eqs.squad_id
                 LEFT JOIN training_stats AS ts
                           ON ms.squad_id = ts.squad_id
                 LEFT JOIN squad_dwarfs_stats AS sds
                           ON ms.squad_id = sds.squad_id
                 LEFT JOIN training_correlation AS tr_corr
                           ON ms.squad_id = tr_corr.squad_id
    )

SELECT
    sq_eff.*,

    ROUND(
            (
                0.35 * (sq_eff.victory_percentage::NUMERIC / 100.0)
                    + 0.10 * (1.0 - sq_eff.casualty_rate::NUMERIC / 100.0)
                    + 0.20 * LEAST(
                        sq_eff.casualty_exchange_ratio::NUMERIC / 3.0,
                        1.0
                             )
                    + 0.07 * (sq_eff.retention_rate::NUMERIC / 100.0)
                    + 0.08 * sq_eff.avg_training_effectiveness::NUMERIC
          + 0.10 * sq_eff.training_battle_correlation::NUMERIC
          + 0.10 * LEAST(
                sq_eff.avg_combat_skill_improvement::NUMERIC / 5.0,
                1.0
            )
                )::NUMERIC,
            2
    ) AS overall_effectiveness_score

FROM squad_effective AS sq_eff
ORDER BY
    overall_effectiveness_score;


--reference
WITH squad_battle_stats AS (
    SELECT
        sb.squad_id,
        COUNT(sb.report_id) AS total_battles,
        SUM(CASE WHEN sb.outcome = 'Victory' THEN 1 ELSE 0 END) AS victories,
        SUM(CASE WHEN sb.outcome = 'Defeat' THEN 1 ELSE 0 END) AS defeats,
        SUM(CASE WHEN sb.outcome = 'Retreat' THEN 1 ELSE 0 END) AS retreats,
        SUM(sb.casualties) AS total_casualties,
        SUM(sb.enemy_casualties) AS total_enemy_casualties,
        MIN(sb.date) AS first_battle,
        MAX(sb.date) AS last_battle
    FROM
        squad_battles sb
    GROUP BY
        sb.squad_id
),
     squad_member_history AS (
         SELECT
             sm.squad_id,
             COUNT(DISTINCT sm.dwarf_id) AS total_members_ever,
             COUNT(DISTINCT CASE WHEN sm.exit_reason IS NULL THEN sm.dwarf_id END) AS current_members,
             COUNT(DISTINCT CASE WHEN sm.exit_reason = 'Death' THEN sm.dwarf_id END) AS deaths,
             AVG(EXTRACT(DAY FROM (COALESCE(sm.exit_date, CURRENT_DATE) - sm.join_date))) AS avg_service_days
         FROM
             squad_members sm
         GROUP BY
             sm.squad_id
     ),
     squad_skill_progression AS (
         SELECT
             sm.squad_id,
             sm.dwarf_id,
             AVG(ds_current.level - ds_join.level) AS avg_skill_improvement,
             MAX(ds_current.level) AS max_current_skill
         FROM
             squad_members sm
                 JOIN
             dwarf_skills ds_join ON sm.dwarf_id = ds_join.dwarf_id AND ds_join.date <= sm.join_date
                 JOIN
             dwarf_skills ds_current ON sm.dwarf_id = ds_current.dwarf_id
                 AND ds_current.skill_id = ds_join.skill_id
                 AND ds_current.date = (
                     SELECT MAX(date)
                     FROM dwarf_skills
                     WHERE dwarf_id = sm.dwarf_id AND skill_id = ds_join.skill_id
                 )
                 JOIN
             skills s ON ds_join.skill_id = s.skill_id
         WHERE
             s.category IN ('Combat', 'Military')
         GROUP BY
             sm.squad_id, sm.dwarf_id
     ),
     squad_equipment_quality AS (
         SELECT
             se.squad_id,
             AVG(e.quality::INTEGER) AS avg_equipment_quality,
             MIN(e.quality::INTEGER) AS min_equipment_quality,
             COUNT(DISTINCT e.equipment_id) AS unique_equipment_count,
             SUM(CASE WHEN e.type = 'Weapon' THEN 1 ELSE 0 END) AS weapon_count,
             SUM(CASE WHEN e.type = 'Armor' THEN 1 ELSE 0 END) AS armor_count,
             SUM(CASE WHEN e.type = 'Shield' THEN 1 ELSE 0 END) AS shield_count
         FROM
             squad_equipment se
                 JOIN
             equipment e ON se.equipment_id = e.equipment_id
         GROUP BY
             se.squad_id
     ),
     squad_training_effectiveness AS (
         SELECT
             st.squad_id,
             COUNT(st.schedule_id) AS total_training_sessions,
             AVG(st.effectiveness::DECIMAL) AS avg_training_effectiveness,
             SUM(st.duration_hours) AS total_training_hours,
             -- Calculate if training improves battle outcomes
             CORR(
                     st.effectiveness::DECIMAL,
                     CASE WHEN sb.outcome = 'Victory' THEN 1 ELSE 0 END
             ) AS training_battle_correlation
         FROM
             squad_training st
                 LEFT JOIN
             squad_battles sb ON st.squad_id = sb.squad_id AND sb.date > st.date
         GROUP BY
             st.squad_id
     )
SELECT
    s.squad_id,
    s.name AS squad_name,
    s.formation_type,
    -- Leadership effectiveness
    d.name AS leader_name,
    sbs.total_battles,
    sbs.victories,
    sbs.defeats,
    ROUND((sbs.victories::DECIMAL / NULLIF(sbs.total_battles, 0)) * 100, 2) AS victory_percentage,
    ROUND((sbs.total_casualties::DECIMAL / NULLIF(smh.total_members_ever, 0)) * 100, 2) AS casualty_rate,
    ROUND((sbs.total_enemy_casualties::DECIMAL / NULLIF(sbs.total_casualties, 1)), 2) AS casualty_exchange_ratio,
    -- Member stats
    smh.current_members,
    smh.total_members_ever,
    ROUND((smh.current_members::DECIMAL / NULLIF(smh.total_members_ever, 0)) * 100, 2) AS retention_rate,
    smh.avg_service_days,
    -- Equipment effectiveness
    seq.avg_equipment_quality,
    seq.min_equipment_quality,
    seq.weapon_count + seq.armor_count + seq.shield_count AS total_equipment_pieces,
    -- Training effectiveness
    ste.total_training_sessions,
    ste.total_training_hours,
    ste.avg_training_effectiveness,
    ste.training_battle_correlation,
    -- Skill progression
    ROUND(AVG(ssp.avg_skill_improvement), 2) AS avg_combat_skill_improvement,
    ROUND(AVG(ssp.max_current_skill), 2) AS avg_max_combat_skill,
    -- Years active
    EXTRACT(YEAR FROM (sbs.last_battle - sbs.first_battle)) AS years_active,
    -- Overall effectiveness score
    ROUND(
            (sbs.victories::DECIMAL / NULLIF(sbs.total_battles, 0)) * 0.25 +
            (1 - (sbs.total_casualties::DECIMAL / NULLIF(smh.total_members_ever, 0))) * 0.20 +
            (smh.current_members::DECIMAL / NULLIF(smh.total_members_ever, 0)) * 0.15 +
            (seq.avg_equipment_quality::DECIMAL / 5) * 0.15 +
            (ste.avg_training_effectiveness) * 0.15 +
            (AVG(ssp.avg_skill_improvement) / 5) * 0.10,
            3
    ) AS overall_effectiveness_score,
    -- Related entities for REST API
    JSON_OBJECT(
            'member_ids', (
        SELECT JSON_ARRAYAGG(sm.dwarf_id)
        FROM squad_members sm
        WHERE sm.squad_id = s.squad_id AND sm.exit_date IS NULL
    ),
            'equipment_ids', (
                SELECT JSON_ARRAYAGG(se.equipment_id)
                FROM squad_equipment se
                WHERE se.squad_id = s.squad_id
            ),
            'battle_report_ids', (
                SELECT JSON_ARRAYAGG(sb.report_id)
                FROM squad_battles sb
                WHERE sb.squad_id = s.squad_id
            ),
            'training_ids', (
                SELECT JSON_ARRAYAGG(st.schedule_id)
                FROM squad_training st
                WHERE st.squad_id = s.squad_id
            )
    ) AS related_entities
FROM
    military_squads s
        JOIN
    dwarves d ON s.leader_id = d.dwarf_id
        LEFT JOIN
    squad_battle_stats sbs ON s.squad_id = sbs.squad_id
        LEFT JOIN
    squad_member_history smh ON s.squad_id = smh.squad_id
        LEFT JOIN
    squad_equipment_quality seq ON s.squad_id = seq.squad_id
        LEFT JOIN
    squad_training_effectiveness ste ON s.squad_id = ste.squad_id
        LEFT JOIN
    squad_skill_progression ssp ON s.squad_id = ssp.squad_id
GROUP BY
    s.squad_id, s.name, s.formation_type, d.name,
    sbs.total_battles, sbs.victories, sbs.defeats, sbs.total_casualties,
    sbs.total_enemy_casualties, sbs.first_battle, sbs.last_battle,
    smh.current_members, smh.total_members_ever, smh.avg_service_days,
    seq.avg_equipment_quality, seq.min_equipment_quality, seq.weapon_count,
    seq.armor_count, seq.shield_count,
    ste.total_training_sessions, ste.total_training_hours,
    ste.avg_training_effectiveness, ste.training_battle_correlation
ORDER BY
    overall_effectiveness_score DESC;