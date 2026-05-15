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