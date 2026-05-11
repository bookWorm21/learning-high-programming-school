--solution
WITH base AS (
    SELECT
        exp.expedition_id,
        exp.destination,
        exp.status,

        ROUND(
                COUNT(expmemb.dwarf_id) FILTER (WHERE expmemb.survived)::numeric
                    / NULLIF(COUNT(expmemb.dwarf_id), 0),
                2
        ) * 100 AS survival_rate,

        SUM(expart.value)       AS artifacts_value,
        COUNT(expsites.site_id) AS discovered_sites,

        ROUND(
                COUNT(expcreat.creature_id) FILTER (WHERE expcreat.outcome = 'success')::numeric
                    / NULLIF(COUNT(expcreat.creature_id) FILTER (WHERE expcreat.outcome = 'failed'), 0),
                2
        ) AS encounter_success_rate,

        COUNT(dwsk.level) FILTER (
            WHERE expmemb.survived
                AND dwsk.date BETWEEN exp.departure_date AND exp.return_date
            ) AS skill_improvement,

        (exp.return_date - exp.departure_date) AS expedition_duration,

        JSON_BUILD_OBJECT(
                'member_ids', COALESCE(JSON_AGG(expmemb.dwarf_id), '[]'::json),
                'artifact_ids', COALESCE(JSON_AGG(expart.artifact_id), '[]'::json),
                'site_ids', COALESCE(JSON_AGG(expsites.site_id), '[]'::json)
        ) AS related_entities

    FROM expeditions AS exp
             INNER JOIN expedition_artifacts AS expart
                        ON exp.expedition_id = expart.expedition_id
             INNER JOIN expedition_sites AS expsites
                        ON exp.expedition_id = expsites.expedition_id
             INNER JOIN expedition_members AS expmemb
                        ON exp.expedition_id = expmemb.expedition_id
             INNER JOIN expedition_creatures AS expcreat
                        ON exp.expedition_id = expcreat.expedition_id
             INNER JOIN dwarf_skills AS dwsk
                        ON expmemb.dwarf_id = dwsk.dwarf_id

    WHERE exp.status = 'Completed'

    GROUP BY
        exp.expedition_id,
        exp.destination,
        exp.status,
        exp.return_date,
        exp.departure_date
),

     max_values AS (
         SELECT
             MAX(skill_improvement) AS max_skill_improvement,
             MAX(expedition_duration) AS max_expedition_duration,
             MAX(discovered_sites) AS max_discovered_sites
         FROM base
     )
SELECT
    base.expedition_id,
    base.destination,
    base.status,
    base.survival_rate,
    base.artifacts_value,
    base.discovered_sites,
    base.encounter_success_rate,
    base.skill_improvement,
    base.expedition_duration,

    base.survival_rate / 100 * 0.2 +
    base.encounter_success_rate / 100 * 0.2 +
    base.skill_improvement / NULLIF(max_values.max_skill_improvement, 0) * 0.2 +
    base.expedition_duration / NULLIF(max_values.max_expedition_duration, 0) * 0.2 +
    base.discovered_sites / NULLIF(max_values.max_discovered_sites, 0) * 0.2
        AS overall_success_score,

    base.related_entities

FROM base
CROSS JOIN max_values
ORDER BY overall_success_score;

--reference
WITH expedition_stats AS (
    SELECT
        e.expedition_id,
        e.destination,
        e.status,
        COUNT(em.dwarf_id) AS total_members,
        SUM(CASE WHEN em.survived = TRUE THEN 1 ELSE 0 END) AS survivors,
        COALESCE(SUM(ea.value), 0) AS artifacts_value,
        COUNT(DISTINCT es.site_id) AS discovered_sites,
        SUM(CASE WHEN ec.outcome = 'Favorable' THEN 1 ELSE 0 END) AS favorable_encounters,
        COUNT(ec.creature_id) AS total_encounters,
        e.departure_date,
        e.return_date
    FROM
        expeditions e
            LEFT JOIN
        expedition_members em ON e.expedition_id = em.expedition_id
            LEFT JOIN
        expedition_artifacts ea ON e.expedition_id = ea.expedition_id
            LEFT JOIN
        expedition_sites es ON e.expedition_id = es.expedition_id
            LEFT JOIN
        expedition_creatures ec ON e.expedition_id = ec.expedition_id
    GROUP BY
        e.expedition_id, e.destination, e.status, e.departure_date, e.return_date
),
     skills_progression AS (
         SELECT
             em.expedition_id,
             SUM(
                     COALESCE(ds_after.level, 0) - COALESCE(ds_before.level, 0)
             ) AS total_skill_improvement
         FROM
             expedition_members em
                 JOIN
             dwarves d ON em.dwarf_id = d.dwarf_id
                 JOIN
             dwarf_skills ds_before ON d.dwarf_id = ds_before.dwarf_id
                 JOIN
             dwarf_skills ds_after ON d.dwarf_id = ds_after.dwarf_id
                 AND ds_before.skill_id = ds_after.skill_id
                 JOIN
             expeditions e ON em.expedition_id = e.expedition_id
         WHERE
             ds_before.date < e.departure_date
           AND ds_after.date > e.return_date
         GROUP BY
             em.expedition_id
     )
SELECT
    es.expedition_id,
    es.destination,
    es.status,
    es.survivors AS surviving_members,
    es.total_members,
    ROUND((es.survivors::DECIMAL / es.total_members) * 100, 2) AS survival_rate,
    es.artifacts_value,
    es.discovered_sites,
    COALESCE(ROUND((es.favorable_encounters::DECIMAL /
        NULLIF(es.total_encounters, 0)) * 100, 2), 0) AS encounter_success_rate,
    COALESCE(sp.total_skill_improvement, 0) AS skill_improvement,
    EXTRACT(DAY FROM (es.return_date - es.departure_date)) AS expedition_duration,
    ROUND(
            (es.survivors::DECIMAL / es.total_members) * 0.3 +
            (es.artifacts_value / 1000) * 0.25 +
            (es.discovered_sites * 0.15) +
            COALESCE((es.favorable_encounters::DECIMAL /
            NULLIF(es.total_encounters, 0)), 0) * 0.15 +
            COALESCE((sp.total_skill_improvement / es.total_members), 0) * 0.15,
            2
    ) AS overall_success_score,
    JSON_OBJECT(
            'member_ids', (
        SELECT JSON_ARRAYAGG(em.dwarf_id)
        FROM expedition_members em
        WHERE em.expedition_id = es.expedition_id
    ),
            'artifact_ids', (
                SELECT JSON_ARRAYAGG(ea.artifact_id)
                FROM expedition_artifacts ea
                WHERE ea.expedition_id = es.expedition_id
            ),
            'site_ids', (
                SELECT JSON_ARRAYAGG(es2.site_id)
                FROM expedition_sites es2
                WHERE es2.expedition_id = es.expedition_id
            )
    ) AS related_entities
FROM
    expedition_stats es
        LEFT JOIN
    skills_progression sp ON es.expedition_id = sp.expedition_id
ORDER BY
    overall_success_score DESC;

--reflection