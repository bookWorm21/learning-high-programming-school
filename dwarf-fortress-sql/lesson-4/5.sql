WITH
    location_fortress_map AS (
        SELECT
            l.location_id,
            f.fortress_id
        FROM fortresses AS f
                 JOIN locations AS l
                      ON l.location_id = f.location::BIGINT
    ),

    attack_extended_stats AS (
SELECT
    lfm.fortress_id,
    ca.attack_id,
    ca.creature_id,
    cr.type AS creature_type,
    cr.name AS creature_name,
    cr.threat_level,
    cr.active,
    cr.estimated_population,
    ca.location_id,
    l.zone_id,
    l.name AS zone_name,
    l.zone_type,
    ca.date,
    EXTRACT(YEAR FROM ca.date)::INT AS attack_year,
    EXTRACT(MONTH FROM ca.date)::INT AS attack_month,

    CASE
    WHEN EXTRACT(MONTH FROM ca.date) IN (12, 1, 2) THEN 'winter'
    WHEN EXTRACT(MONTH FROM ca.date) IN (3, 4, 5) THEN 'spring'
    WHEN EXTRACT(MONTH FROM ca.date) IN (6, 7, 8) THEN 'summer'
    ELSE 'autumn'
    END AS season,

    ca.casualties,
    ca.enemy_casualties,
    ca.outcome,
    ca.value,
    ca.military_response_time_minutes,

    CASE
    WHEN ca.outcome IN ('victory') THEN 1
    ELSE 0
    END AS is_defense_success,

    CASE
    WHEN ca.outcome IN ('loss') THEN 1
    ELSE 0
    END AS is_breach
FROM creature_attacks AS ca
    LEFT JOIN creatures AS cr
ON cr.creature_id = ca.creature_id
    LEFT JOIN locations AS l
    ON l.location_id = ca.location_id
    LEFT JOIN location_fortress_map AS lfm
    ON lfm.location_id = ca.location_id
    ),

    fortress_security_stats AS (
SELECT
    f.fortress_id,
    f.name AS fortress_name,

    COUNT(atts.attack_id) AS total_recorded_attacks,

    COUNT(DISTINCT atts.creature_id) FILTER (
    WHERE atts.creature_id IS NOT NULL
    ) AS unique_attackers,

    COALESCE(
    ROUND(
    AVG(atts.is_defense_success)::NUMERIC * 100,
    2
    ),
    0
    ) AS overall_defense_success_rate
FROM fortresses AS f
    LEFT JOIN attack_extended_stats AS atts
ON atts.fortress_id = f.fortress_id
GROUP BY
    f.fortress_id,
    f.name
    ),

    creature_last_sightings AS (
SELECT
    d.fortress_id,
    cs.creature_id,
    MAX(cs.date) AS last_sighting_date
FROM creature_sightings AS cs
    LEFT JOIN dwarves AS d
ON d.dwarf_id = cs.witness_id
WHERE d.fortress_id IS NOT NULL
GROUP BY
    d.fortress_id,
    cs.creature_id
    ),

    creature_territory_stats AS (
SELECT
    ct.creature_id,
    AVG(ct.distance_to_fortress) AS territory_proximity
FROM creature_territories AS ct
GROUP BY
    ct.creature_id
    ),

    creature_fortress_activity AS (
SELECT DISTINCT
    atts.fortress_id,
    atts.creature_id
FROM attack_extended_stats AS atts
WHERE atts.fortress_id IS NOT NULL
  AND atts.creature_id IS NOT NULL

UNION

SELECT DISTINCT
    cls.fortress_id,
    cls.creature_id
FROM creature_last_sightings AS cls
WHERE cls.fortress_id IS NOT NULL
  AND cls.creature_id IS NOT NULL
    ),

    active_threats AS (
SELECT
    cfa.fortress_id,
    cr.type AS creature_type,

    COALESCE(
    ROUND(
    AVG(cr.threat_level)::NUMERIC / 100,
    2
    ),
    0
    ) AS threat_level_normalized,

    MAX(cls.last_sighting_date) AS last_sighting_date,
    AVG(cts.territory_proximity) AS territory_proximity,
    COALESCE(SUM(cr.estimated_population), 0) AS estimated_numbers,

    COALESCE(
    JSONB_AGG(DISTINCT cr.creature_id)
    FILTER (WHERE cr.creature_id IS NOT NULL),
    '[]'::JSONB
    ) AS creature_ids
FROM creature_fortress_activity AS cfa
    JOIN creatures AS cr
ON cr.creature_id = cfa.creature_id
    LEFT JOIN creature_last_sightings AS cls
    ON cls.creature_id = cr.creature_id
    AND cls.fortress_id = cfa.fortress_id
    LEFT JOIN creature_territory_stats AS cts
    ON cts.creature_id = cr.creature_id
WHERE cr.active = TRUE
GROUP BY
    cfa.fortress_id,
    cr.type
    ),

    current_threat_score AS (
SELECT
    at.fortress_id,

    COALESCE(
    AVG(
    at.threat_level_normalized
    + CASE
    WHEN at.territory_proximity IS NULL THEN 0
    WHEN at.territory_proximity <= 1 THEN 2
    WHEN at.territory_proximity <= 3 THEN 1
    ELSE 0
    END
    ),
    0
    ) AS avg_current_threat_score
FROM active_threats AS at
GROUP BY
    at.fortress_id
    ),

    location_attack_stats AS (
SELECT
    atts.fortress_id,
    atts.location_id,

    COUNT(atts.attack_id) AS historical_attacks,

    COUNT(atts.attack_id) FILTER (
    WHERE atts.is_breach = 1
    ) AS historical_breaches,

    COALESCE(
    ROUND(
    AVG(atts.military_response_time_minutes)::NUMERIC,
    2
    ),
    0
    ) AS avg_military_response_time,

    COALESCE(
    ROUND(
    AVG(atts.is_defense_success)::NUMERIC,
    2
    ),
    0
    ) AS defense_success_rate
FROM attack_extended_stats AS atts
WHERE atts.fortress_id IS NOT NULL
GROUP BY
    atts.fortress_id,
    atts.location_id
    ),

    location_defense_coverage AS (
SELECT
    lfm.fortress_id,
    ds.location_id,

    COUNT(DISTINCT ds.structure_id) AS defense_structures_count,

    COALESCE(
    JSONB_AGG(DISTINCT ds.structure_id)
    FILTER (WHERE ds.structure_id IS NOT NULL),
    '[]'::JSONB
    ) AS structure_ids
FROM defense_structures AS ds
    JOIN location_fortress_map AS lfm
ON lfm.location_id = ds.location_id
GROUP BY
    lfm.fortress_id,
    ds.location_id
    ),

    location_squad_coverage AS (
SELECT
    ms.fortress_id,
    mcz.location_id,

    COUNT(DISTINCT mcz.squad_id) FILTER (
    WHERE mcz.squad_id IS NOT NULL
    ) AS covering_squads_count,

    COALESCE(
    ROUND(
    AVG(mcz.response_time_minutes)::NUMERIC,
    2
    ),
    0
    ) AS avg_coverage_response_time,

    COALESCE(
    JSONB_AGG(DISTINCT mcz.squad_id)
    FILTER (WHERE mcz.squad_id IS NOT NULL),
    '[]'::JSONB
    ) AS squad_ids
FROM military_coverage_zones AS mcz
    JOIN military_squads AS ms
ON ms.squad_id = mcz.squad_id
WHERE mcz.active_to IS NULL
  AND ms.fortress_id IS NOT NULL
GROUP BY
    ms.fortress_id,
    mcz.location_id
    ),

    vulnerability_analysis AS (
SELECT
    lfm.fortress_id,
    l.zone_id,
    l.name AS zone_name,

    ROUND(
    LEAST(
    1.0,
    COALESCE(las.historical_breaches, 0)::NUMERIC * 0.08
    + COALESCE(l.access_points, 0)::NUMERIC * 0.04
    + (100 - COALESCE(l.fortification_level, 0))::NUMERIC / 100.0 * 0.20
    + (100 - COALESCE(l.wall_integrity, 0))::NUMERIC / 100.0 * 0.20
    + (1.0 / NULLIF(COALESCE(l.trap_density, 0) + 1, 0)) * 0.10
    + (
    COALESCE(
    lsc.avg_coverage_response_time,
    las.avg_military_response_time,
    60
    ) / 60.0
    ) * 0.20
    + CASE
    WHEN COALESCE(ldc.defense_structures_count, 0) = 0 THEN 0.18
    ELSE 0
    END
    ),
    2
    ) AS vulnerability_score,

    COALESCE(las.historical_breaches, 0) AS historical_breaches,
    COALESCE(l.fortification_level, 0) AS fortification_level,

    COALESCE(
    las.avg_military_response_time,
    0
    ) AS military_response_time,

    JSONB_BUILD_OBJECT(
    'structure_ids',
    COALESCE(ldc.structure_ids, '[]'::JSONB),

    'squad_ids',
    COALESCE(lsc.squad_ids, '[]'::JSONB)
    ) AS defense_coverage
FROM location_fortress_map AS lfm
    JOIN locations AS l
ON l.location_id = lfm.location_id
    LEFT JOIN location_attack_stats AS las
    ON las.location_id = l.location_id
    AND las.fortress_id = lfm.fortress_id
    LEFT JOIN location_defense_coverage AS ldc
    ON ldc.location_id = l.location_id
    AND ldc.fortress_id = lfm.fortress_id
    LEFT JOIN location_squad_coverage AS lsc
    ON lsc.location_id = l.location_id
    AND lsc.fortress_id = lfm.fortress_id
    ),

    defense_effectiveness AS (
SELECT
    lfm.fortress_id,
    ds.type AS defense_type,

    COALESCE(
    ROUND(
    AVG(
    CASE
    WHEN atts.is_defense_success = 1 THEN 100.0
    ELSE 0.0
    END
    )::NUMERIC,
    2
    ),
    0
    ) AS effectiveness_rate,

    COALESCE(
    ROUND(
    AVG(atts.enemy_casualties)::NUMERIC,
    2
    ),
    0
    ) AS avg_enemy_casualties,

    COALESCE(
    JSONB_AGG(DISTINCT ds.structure_id)
    FILTER (WHERE ds.structure_id IS NOT NULL),
    '[]'::JSONB
    ) AS structure_ids
FROM defense_structures AS ds
    JOIN location_fortress_map AS lfm
ON lfm.location_id = ds.location_id
    LEFT JOIN creature_attack_defense_structures AS cads
    ON cads.structure_id = ds.structure_id
    LEFT JOIN attack_extended_stats AS atts
    ON atts.attack_id = cads.attack_id
    AND atts.fortress_id = lfm.fortress_id
GROUP BY
    lfm.fortress_id,
    ds.type
    ),

    creature_type_defense_results AS (
SELECT
    atts.fortress_id,
    atts.creature_type,

    COUNT(atts.attack_id) AS total_attacks,

    COALESCE(
    ROUND(
    AVG(atts.is_defense_success)::NUMERIC * 100,
    2
    ),
    0
    ) AS defense_success_rate,

    COALESCE(
    ROUND(
    AVG(atts.casualties)::NUMERIC,
    2
    ),
    0
    ) AS avg_casualties,

    COALESCE(
    ROUND(
    AVG(atts.enemy_casualties)::NUMERIC,
    2
    ),
    0
    ) AS avg_enemy_casualties
FROM attack_extended_stats AS atts
WHERE atts.fortress_id IS NOT NULL
GROUP BY
    atts.fortress_id,
    atts.creature_type
    ),

    squad_active_members AS (
SELECT
    sm.squad_id,

    COUNT(sm.dwarf_id) FILTER (
    WHERE sm.exit_date IS NULL
    ) AS active_members
FROM squad_members AS sm
GROUP BY
    sm.squad_id
    ),

    squad_combat_skills AS (
SELECT
    sm.squad_id,

    COALESCE(
    ROUND(
    AVG(ds.level)::NUMERIC,
    2
    ),
    0
    ) AS avg_combat_skill
FROM squad_members AS sm
    LEFT JOIN dwarf_skills AS ds
ON ds.dwarf_id = sm.dwarf_id
    LEFT JOIN skills AS s
    ON s.skill_id = ds.skill_id
    AND s.skill_type = 'combat'
WHERE sm.exit_date IS NULL
GROUP BY
    sm.squad_id
    ),

    squad_battle_effectiveness AS (
SELECT
    sb.squad_id,

    COALESCE(
    ROUND(
    AVG(
    CASE
    WHEN sb.outcome IN ('victory') THEN 1.0
    ELSE 0.0
    END
    )::NUMERIC,
    2
    ),
    0
    ) AS combat_effectiveness
FROM squad_battles AS sb
GROUP BY
    sb.squad_id
    ),

    squad_training_readiness AS (
SELECT
    st.squad_id,

    COALESCE(
    ROUND(
    AVG(st.effectiveness)::NUMERIC,
    2
    ),
    0
    ) AS avg_training_effectiveness
FROM squad_training AS st
GROUP BY
    st.squad_id
    ),

    squad_equipment_readiness AS (
SELECT
    se.squad_id,
    COALESCE(SUM(se.quantity), 0) AS total_issued_equipment
FROM squad_equipment AS se
GROUP BY
    se.squad_id
    ),

    squad_response_coverage AS (
SELECT
    mcz.squad_id,

    COALESCE(
    JSONB_AGG(
    JSONB_BUILD_OBJECT(
    'zone_id',
    l.zone_id,

    'response_time',
    COALESCE(mcz.response_time_minutes, 0)
    )
    ORDER BY l.zone_id
    ) FILTER (WHERE mcz.location_id IS NOT NULL),
    '[]'::JSONB
    ) AS response_coverage
FROM military_coverage_zones AS mcz
    LEFT JOIN locations AS l
ON l.location_id = mcz.location_id
WHERE mcz.active_to IS NULL
   OR mcz.active_to >= CURRENT_DATE
GROUP BY
    mcz.squad_id
    ),

    military_readiness_assessment AS (
SELECT
    ms.fortress_id,
    ms.squad_id,
    ms.name AS squad_name,

    ROUND(
    LEAST(
    1.0,
    (
    COALESCE(sam.active_members, 0)::NUMERIC / 10.0 * 0.25
    + COALESCE(scs.avg_combat_skill, 0)::NUMERIC / 20.0 * 0.25
    + COALESCE(sbe.combat_effectiveness, 0)::NUMERIC * 0.25
    + COALESCE(str.avg_training_effectiveness, 0)::NUMERIC * 0.15
    + LEAST(
    COALESCE(ser.total_issued_equipment, 0)::NUMERIC / 10.0,
    1.0
    ) * 0.10
    )
    ),
    2
    ) AS readiness_score,

    COALESCE(sam.active_members, 0) AS active_members,
    COALESCE(scs.avg_combat_skill, 0) AS avg_combat_skill,
    COALESCE(sbe.combat_effectiveness, 0) AS combat_effectiveness,
    COALESCE(src.response_coverage, '[]'::JSONB) AS response_coverage
FROM military_squads AS ms
    LEFT JOIN squad_active_members AS sam
ON sam.squad_id = ms.squad_id
    LEFT JOIN squad_combat_skills AS scs
    ON scs.squad_id = ms.squad_id
    LEFT JOIN squad_battle_effectiveness AS sbe
    ON sbe.squad_id = ms.squad_id
    LEFT JOIN squad_training_readiness AS str
    ON str.squad_id = ms.squad_id
    LEFT JOIN squad_equipment_readiness AS ser
    ON ser.squad_id = ms.squad_id
    LEFT JOIN squad_response_coverage AS src
    ON src.squad_id = ms.squad_id
WHERE ms.fortress_id IS NOT NULL
    ),

    seasonal_attack_stats AS (
SELECT
    atts.fortress_id,
    atts.attack_year,
    atts.attack_month,
    atts.season,

    COUNT(atts.attack_id) AS attacks_count,
    COALESCE(AVG(wr.temperature_c), 0) AS avg_temperature_c,

    COUNT(atts.attack_id) FILTER (
    WHERE wr.precipitation IS NOT NULL
    AND wr.precipitation <> 'clear'
    ) AS attacks_during_precipitation,

    COALESCE(AVG(mp.illumination_pct), 0) AS avg_moon_illumination
FROM attack_extended_stats AS atts
    LEFT JOIN weather_records AS wr
ON wr.date = atts.date
    AND wr.fortress_id = atts.fortress_id
    LEFT JOIN moon_phases AS mp
    ON mp.date = atts.date
WHERE atts.fortress_id IS NOT NULL
GROUP BY
    atts.fortress_id,
    atts.attack_year,
    atts.attack_month,
    atts.season
    ),

    seasonal_correlations AS (
SELECT
    sas.fortress_id,

    COALESCE(
    ROUND(
    CORR(
    sas.attacks_count::DOUBLE PRECISION,
    sas.avg_temperature_c::DOUBLE PRECISION
    )::NUMERIC,
    2
    ),
    0
    ) AS temperature_attack_correlation,

    COALESCE(
    ROUND(
    CORR(
    sas.attacks_count::DOUBLE PRECISION,
    sas.avg_moon_illumination::DOUBLE PRECISION
    )::NUMERIC,
    2
    ),
    0
    ) AS moon_attack_correlation,

    COALESCE(
    ROUND(
    CORR(
    sas.attacks_count::DOUBLE PRECISION,
    sas.attacks_during_precipitation::DOUBLE PRECISION
    )::NUMERIC,
    2
    ),
    0
    ) AS precipitation_attack_correlation
FROM seasonal_attack_stats AS sas
GROUP BY
    sas.fortress_id
    ),

    security_evolution_base AS (
SELECT
    atts.fortress_id,
    atts.attack_year AS year,

    COUNT(atts.attack_id) AS total_attacks,

    COALESCE(
    ROUND(
    AVG(atts.is_defense_success)::NUMERIC * 100,
    2
    ),
    0
    ) AS defense_success_rate,

    COALESCE(SUM(atts.casualties), 0) AS casualties
FROM attack_extended_stats AS atts
WHERE atts.fortress_id IS NOT NULL
GROUP BY
    atts.fortress_id,
    atts.attack_year
    ),

    security_evolution AS (
SELECT
    seb.fortress_id,
    seb.year,
    seb.defense_success_rate,
    seb.total_attacks,
    seb.casualties,

    COALESCE(
    ROUND(
    seb.defense_success_rate
    - LAG(seb.defense_success_rate) OVER (
    PARTITION BY seb.fortress_id
    ORDER BY seb.year
    ),
    2
    ),
    0
    ) AS year_over_year_improvement
FROM security_evolution_base AS seb
    )

SELECT
    fss.fortress_id,
    fss.fortress_name,
    fss.total_recorded_attacks,
    fss.unique_attackers,
    fss.overall_defense_success_rate,

    JSONB_BUILD_OBJECT(
            'security_analysis',
            JSONB_BUILD_OBJECT(
                    'threat_assessment',
                    JSONB_BUILD_OBJECT(
                            'current_threat_level',
                            CASE
                                WHEN COALESCE(cts.avg_current_threat_score, 0) >= 5 THEN 'Critical'
                                WHEN COALESCE(cts.avg_current_threat_score, 0) >= 4 THEN 'High'
                                WHEN COALESCE(cts.avg_current_threat_score, 0) >= 2 THEN 'Moderate'
                                WHEN COALESCE(cts.avg_current_threat_score, 0) > 0 THEN 'Low'
                                ELSE 'None'
                                END,

                            'active_threats',
                            COALESCE(
                                    (
                                        SELECT JSONB_AGG(
                                                       JSONB_BUILD_OBJECT(
                                                               'creature_type',
                                                               at.creature_type,

                                                               'threat_level',
                                                               at.threat_level_normalized,

                                                               'last_sighting_date',
                                                               at.last_sighting_date,

                                                               'territory_proximity',
                                                               at.territory_proximity,

                                                               'estimated_numbers',
                                                               at.estimated_numbers,

                                                               'creature_ids',
                                                               at.creature_ids
                                                       )
                                                           ORDER BY
                                                           at.threat_level_normalized DESC,
                                                       at.territory_proximity ASC NULLS LAST
                                               )
                                        FROM active_threats AS at
                                    WHERE at.fortress_id = fss.fortress_id
                                ),
                                    '[]'::JSONB
                            )
                    ),

                    'vulnerability_analysis',
                    COALESCE(
                            (
                                SELECT JSONB_AGG(
                                               JSONB_BUILD_OBJECT(
                                                       'zone_id',
                                                       va.zone_id,

                                                       'zone_name',
                                                       va.zone_name,

                                                       'vulnerability_score',
                                                       va.vulnerability_score,

                                                       'historical_breaches',
                                                       va.historical_breaches,

                                                       'fortification_level',
                                                       va.fortification_level,

                                                       'military_response_time',
                                                       va.military_response_time,

                                                       'defense_coverage',
                                                       va.defense_coverage
                                               )
                                                   ORDER BY va.vulnerability_score DESC
                                       )
                                FROM vulnerability_analysis AS va
                                WHERE va.fortress_id = fss.fortress_id
                            ),
                            '[]'::JSONB
                    ),

                    'defense_effectiveness',
                    COALESCE(
                            (
                                SELECT JSONB_AGG(
                                               JSONB_BUILD_OBJECT(
                                                       'defense_type',
                                                       de.defense_type,

                                                       'effectiveness_rate',
                                                       de.effectiveness_rate,

                                                       'avg_enemy_casualties',
                                                       de.avg_enemy_casualties,

                                                       'structure_ids',
                                                       de.structure_ids
                                               )
                                                   ORDER BY
                                                   de.effectiveness_rate DESC,
                                               de.avg_enemy_casualties DESC
                                       )
                                FROM defense_effectiveness AS de
                                WHERE de.fortress_id = fss.fortress_id
                            ),
                            '[]'::JSONB
                    ),

                    'creature_type_defense_results',
                    COALESCE(
                            (
                                SELECT JSONB_AGG(
                                               JSONB_BUILD_OBJECT(
                                                       'creature_type',
                                                       ctdr.creature_type,

                                                       'total_attacks',
                                                       ctdr.total_attacks,

                                                       'defense_success_rate',
                                                       ctdr.defense_success_rate,

                                                       'avg_casualties',
                                                       ctdr.avg_casualties,

                                                       'avg_enemy_casualties',
                                                       ctdr.avg_enemy_casualties
                                               )
                                                   ORDER BY ctdr.total_attacks DESC
                                       )
                                FROM creature_type_defense_results AS ctdr
                                WHERE ctdr.fortress_id = fss.fortress_id
                            ),
                            '[]'::JSONB
                    ),

                    'seasonal_security_factors',
                    JSONB_BUILD_OBJECT(
                            'correlations',
                            COALESCE(
                                    (
                                        SELECT JSONB_BUILD_OBJECT(
                                                       'temperature_attack_correlation',
                                                       sc.temperature_attack_correlation,

                                                       'moon_attack_correlation',
                                                       sc.moon_attack_correlation,

                                                       'precipitation_attack_correlation',
                                                       sc.precipitation_attack_correlation
                                               )
                                        FROM seasonal_correlations AS sc
                                        WHERE sc.fortress_id = fss.fortress_id
                                    ),
                                    '{}'::JSONB
                            ),

                            'seasonal_attack_stats',
                            COALESCE(
                                    (
                                        SELECT JSONB_AGG(
                                                       JSONB_BUILD_OBJECT(
                                                               'year',
                                                               sas.attack_year,

                                                               'month',
                                                               sas.attack_month,

                                                               'season',
                                                               sas.season,

                                                               'attacks_count',
                                                               sas.attacks_count,

                                                               'avg_temperature_c',
                                                               ROUND(sas.avg_temperature_c::NUMERIC, 2),

                                                               'attacks_during_precipitation',
                                                               sas.attacks_during_precipitation,

                                                               'avg_moon_illumination',
                                                               ROUND(sas.avg_moon_illumination::NUMERIC, 2)
                                                       )
                                                           ORDER BY sas.attack_year, sas.attack_month
                                               )
                                        FROM seasonal_attack_stats AS sas
                                        WHERE sas.fortress_id = fss.fortress_id
                                    ),
                                    '[]'::JSONB
                            )
                    ),

                    'military_readiness_assessment',
                    COALESCE(
                            (
                                SELECT JSONB_AGG(
                                               JSONB_BUILD_OBJECT(
                                                       'squad_id',
                                                       mra.squad_id,

                                                       'squad_name',
                                                       mra.squad_name,

                                                       'readiness_score',
                                                       mra.readiness_score,

                                                       'active_members',
                                                       mra.active_members,

                                                       'avg_combat_skill',
                                                       mra.avg_combat_skill,

                                                       'combat_effectiveness',
                                                       mra.combat_effectiveness,

                                                       'response_coverage',
                                                       mra.response_coverage
                                               )
                                                   ORDER BY mra.readiness_score DESC
                                       )
                                FROM military_readiness_assessment AS mra
                                WHERE mra.fortress_id = fss.fortress_id
                            ),
                            '[]'::JSONB
                    ),

                    'security_evolution',
                    COALESCE(
                            (
                                SELECT JSONB_AGG(
                                               JSONB_BUILD_OBJECT(
                                                       'year',
                                                       se.year,

                                                       'defense_success_rate',
                                                       se.defense_success_rate,

                                                       'total_attacks',
                                                       se.total_attacks,

                                                       'casualties',
                                                       se.casualties,

                                                       'year_over_year_improvement',
                                                       se.year_over_year_improvement
                                               )
                                                   ORDER BY se.year
                                       )
                                FROM security_evolution AS se
                                WHERE se.fortress_id = fss.fortress_id
                            ),
                            '[]'::JSONB
                    )
            )
    ) AS fortress_security_analysis
FROM fortress_security_stats AS fss
         LEFT JOIN current_threat_score AS cts
                   ON cts.fortress_id = fss.fortress_id
ORDER BY
    fss.fortress_id;
