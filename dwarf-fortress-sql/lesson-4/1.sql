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
         CROSS JOIN max_values;