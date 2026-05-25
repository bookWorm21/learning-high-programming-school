WITH
    transaction_stats AS (
        SELECT
            tt.transaction_id,
            tt.caravan_id,
            tt.date,
            tt.value,

            CASE
                WHEN tt.balance_direction = 'favorable'
                    THEN tt.value

                WHEN tt.balance_direction = 'unfavorable'
                    THEN -tt.value

                ELSE 0
                END AS trade_balance
        FROM trade_transactions AS tt
    ),

    caravan_trade_stats AS (
        SELECT
            c.caravan_id,
            c.civilization_type,
            c.arrival_date,
            c.departure_date,

            COUNT(ts.transaction_id) AS transactions_count,
            COALESCE(SUM(ts.value), 0) AS caravan_trade_value,
            COALESCE(SUM(ts.trade_balance), 0) AS caravan_trade_balance
        FROM caravans AS c
                 LEFT JOIN transaction_stats AS ts
                           ON ts.caravan_id = c.caravan_id
        GROUP BY
            c.caravan_id,
            c.civilization_type,
            c.arrival_date,
            c.departure_date
    ),

    caravan_diplomacy_stats AS (
        SELECT
            c.caravan_id,
            c.civilization_type,

            COUNT(de.event_id) AS diplomatic_events_count,
            COALESCE(SUM(de.relationship_change), 0) AS caravan_relationship_change,
            COALESCE(AVG(de.relationship_change), 0) AS avg_relationship_change
        FROM caravans AS c
                 LEFT JOIN diplomatic_events AS de
                           ON de.caravan_id = c.caravan_id
        GROUP BY
            c.caravan_id,
            c.civilization_type
    ),

    global_trade_stats AS (
        SELECT
            COUNT(DISTINCT cts.civilization_type) FILTER (
                WHERE cts.civilization_type IS NOT NULL
                ) AS total_trading_partners,

            COALESCE(SUM(cts.caravan_trade_value), 0) AS all_time_trade_value,
            COALESCE(SUM(cts.caravan_trade_balance), 0) AS all_time_trade_balance
        FROM caravan_trade_stats AS cts
    ),

    civilization_base AS (
        SELECT
            cts.civilization_type,

            COUNT(cts.caravan_id) AS total_caravans,
            COALESCE(SUM(cts.caravan_trade_value), 0) AS total_trade_value,
            COALESCE(SUM(cts.caravan_trade_balance), 0) AS trade_balance,

            COALESCE(
                    JSONB_AGG(cts.caravan_id ORDER BY cts.caravan_id)
                    FILTER (WHERE cts.caravan_id IS NOT NULL),
                    '[]'::JSONB
            ) AS caravan_ids
        FROM caravan_trade_stats AS cts
        GROUP BY
            cts.civilization_type
    ),

    diplomatic_trade_correlation AS (
        SELECT
            cts.civilization_type,

            COALESCE(
                    ROUND(
                            CORR(
                                    cts.caravan_trade_balance::DOUBLE PRECISION,
                                    cds.caravan_relationship_change::DOUBLE PRECISION
                            )::NUMERIC,
                            2
                    ),
                    0
            ) AS diplomatic_correlation,

            COALESCE(SUM(cds.caravan_relationship_change), 0) AS total_relationship_change
        FROM caravan_trade_stats AS cts
                 LEFT JOIN caravan_diplomacy_stats AS cds
                           ON cds.caravan_id = cts.caravan_id
        GROUP BY
            cts.civilization_type
    ),

    civilization_trade_data AS (
        SELECT
            cb.civilization_type,
            cb.total_caravans,
            cb.total_trade_value,
            cb.trade_balance,

            CASE
                WHEN cb.trade_balance > 0 THEN 'Favorable'
                WHEN cb.trade_balance < 0 THEN 'Unfavorable'
                ELSE 'Neutral'
                END AS trade_relationship,

            dtc.diplomatic_correlation,
            cb.caravan_ids
        FROM civilization_base AS cb
                 LEFT JOIN diplomatic_trade_correlation AS dtc
                           ON dtc.civilization_type = cb.civilization_type
    ),

    goods_economic_impact AS (
        SELECT
            cg.type AS trade_goods_direction,
            cg.material_type,
            cg.name AS goods_name,

            COUNT(DISTINCT cg.caravan_id) AS caravans_count,
            COALESCE(SUM(cg.quantity), 0) AS total_quantity,
            COALESCE(SUM(cg.value), 0) AS total_goods_value,

            COALESCE(
                    SUM(
                            CASE
                                WHEN cg.type = 'export' THEN cg.value
                                WHEN cg.type = 'import' THEN -cg.value
                                ELSE 0
                                END
                    ),
                    0
            ) AS fortress_economic_effect,

            COALESCE(
                    JSONB_AGG(DISTINCT c.civilization_type)
                    FILTER (WHERE c.civilization_type IS NOT NULL),
                    '[]'::JSONB
            ) AS civilization_types
        FROM caravan_goods AS cg
                 LEFT JOIN caravans AS c
                           ON c.caravan_id = cg.caravan_id
        GROUP BY
            cg.type,
            cg.material_type,
            cg.name
    ),

    resource_dependency AS (
        SELECT
            cg.material_type,

            COALESCE(SUM(cg.quantity), 0) AS total_imported,
            COALESCE(SUM(cg.value), 0) AS total_import_value,

            COUNT(DISTINCT c.civilization_type) FILTER (
                WHERE c.civilization_type IS NOT NULL
                ) AS import_diversity,

            ROUND(
                    (
                        COALESCE(SUM(cg.value), 0)::NUMERIC
                            * LN(COALESCE(SUM(cg.quantity), 0)::NUMERIC + 1)
                            / NULLIF(
                                        COUNT(DISTINCT c.civilization_type) FILTER (
                                    WHERE c.civilization_type IS NOT NULL
                                    ),
                                        0
                              )
                        ),
                    2
            ) AS dependency_score,

            COALESCE(
                    JSONB_AGG(DISTINCT r.resource_id)
                    FILTER (WHERE r.resource_id IS NOT NULL),
                    '[]'::JSONB
            ) AS resource_ids
        FROM caravan_goods AS cg
                 LEFT JOIN caravans AS c
                           ON c.caravan_id = cg.caravan_id
                 LEFT JOIN resources AS r
                           ON r.type = cg.material_type
        WHERE cg.type = 'import'
        GROUP BY
            cg.material_type
    ),

    product_production AS (
        SELECT
            wp.product_id,
            SUM(wp.quantity) AS total_produced
        FROM workshop_products AS wp
        GROUP BY
            wp.product_id
    ),

    product_exports AS (
        SELECT
            cg.original_product_id AS product_id,
            SUM(cg.quantity) AS total_exported,
            SUM(cg.value) AS total_export_value,
            AVG(
                    cg.value::NUMERIC
                / NULLIF(cg.quantity, 0)
            ) AS avg_export_unit_value
        FROM caravan_goods AS cg
        WHERE cg.type = 'export'
          AND cg.original_product_id IS NOT NULL
        GROUP BY
            cg.original_product_id
    ),

    export_effectiveness AS (
        SELECT
            w.type AS workshop_type,
            p.type AS product_type,

            COALESCE(
                    ROUND(
                            SUM(pe.total_exported)::NUMERIC
                                / NULLIF(SUM(pp.total_produced), 0)
                                * 100,
                            2
                    ),
                    0
            ) AS export_ratio,

            COALESCE(
                    ROUND(
                            AVG(
                                    pe.avg_export_unit_value
                                        / NULLIF(p.value, 0)
                            ),
                            2
                    ),
                    0
            ) AS avg_markup,

            COALESCE(
                    JSONB_AGG(DISTINCT w.workshop_id)
                    FILTER (WHERE w.workshop_id IS NOT NULL),
                    '[]'::JSONB
            ) AS workshop_ids
        FROM product_exports AS pe
                 JOIN products AS p
                      ON p.product_id = pe.product_id
                 LEFT JOIN workshops AS w
                           ON w.workshop_id = p.workshop_id
                 LEFT JOIN product_production AS pp
                           ON pp.product_id = p.product_id
        GROUP BY
            w.type,
            p.type
    ),

    trade_timeline AS (
        SELECT
            EXTRACT(YEAR FROM ts.date)::INT AS year,
    EXTRACT(QUARTER FROM ts.date)::INT AS quarter,

    COALESCE(SUM(ts.value), 0) AS quarterly_value,
    COALESCE(SUM(ts.trade_balance), 0) AS quarterly_balance,

    COUNT(DISTINCT c.civilization_type) FILTER (
    WHERE c.civilization_type IS NOT NULL
    ) AS trade_diversity
FROM transaction_stats AS ts
    LEFT JOIN caravans AS c
ON c.caravan_id = ts.caravan_id
GROUP BY
    EXTRACT(YEAR FROM ts.date),
    EXTRACT(QUARTER FROM ts.date)
    ),

    trade_timeline_with_growth AS (
SELECT
    tt.year,
    tt.quarter,
    tt.quarterly_value,
    tt.quarterly_balance,
    tt.trade_diversity,

    LAG(tt.quarterly_value) OVER (
    ORDER BY tt.year, tt.quarter
    ) AS previous_quarterly_value,

    COALESCE(
    ROUND(
    (
    tt.quarterly_value
    - LAG(tt.quarterly_value) OVER (
    ORDER BY tt.year, tt.quarter
    )
    )::NUMERIC
    / NULLIF(
    LAG(tt.quarterly_value) OVER (
    ORDER BY tt.year, tt.quarter
    ),
    0
    ),
    2
    ),
    0
    ) AS quarterly_growth_rate
FROM trade_timeline AS tt
    )

SELECT
    JSONB_BUILD_OBJECT(
            'total_trading_partners',
            gts.total_trading_partners,

            'all_time_trade_value',
            gts.all_time_trade_value,

            'all_time_trade_balance',
            gts.all_time_trade_balance,

            'civilization_data',
            JSONB_BUILD_OBJECT(
                    'civilization_trade_data',
                    COALESCE(
                            (
                                SELECT JSONB_AGG(
                                               JSONB_BUILD_OBJECT(
                                                       'civilization_type',
                                                       ctd.civilization_type,

                                                       'total_caravans',
                                                       ctd.total_caravans,

                                                       'total_trade_value',
                                                       ctd.total_trade_value,

                                                       'trade_balance',
                                                       ctd.trade_balance,

                                                       'trade_relationship',
                                                       ctd.trade_relationship,

                                                       'diplomatic_correlation',
                                                       ctd.diplomatic_correlation,

                                                       'caravan_ids',
                                                       ctd.caravan_ids
                                               )
                                                   ORDER BY ctd.total_trade_value DESC
                                       )
                                FROM civilization_trade_data AS ctd
                            ),
                            '[]'::JSONB
                    )
            ),

            'goods_economic_impact',
            JSONB_BUILD_OBJECT(
                    'goods_type_data',
                    COALESCE(
                            (
                                SELECT JSONB_AGG(
                                               JSONB_BUILD_OBJECT(
                                                       'trade_goods_direction',
                                                       gei.trade_goods_direction,

                                                       'material_type',
                                                       gei.material_type,

                                                       'goods_name',
                                                       gei.goods_name,

                                                       'caravans_count',
                                                       gei.caravans_count,

                                                       'total_quantity',
                                                       gei.total_quantity,

                                                       'total_goods_value',
                                                       gei.total_goods_value,

                                                       'fortress_economic_effect',
                                                       gei.fortress_economic_effect,

                                                       'civilization_types',
                                                       gei.civilization_types
                                               )
                                                   ORDER BY ABS(gei.fortress_economic_effect) DESC
                                       )
                                FROM goods_economic_impact AS gei
                            ),
                            '[]'::JSONB
                    )
            ),

            'critical_import_dependencies',
            JSONB_BUILD_OBJECT(
                    'resource_dependency',
                    COALESCE(
                            (
                                SELECT JSONB_AGG(
                                               JSONB_BUILD_OBJECT(
                                                       'material_type',
                                                       rd.material_type,

                                                       'dependency_score',
                                                       COALESCE(rd.dependency_score, 0),

                                                       'total_imported',
                                                       rd.total_imported,

                                                       'import_diversity',
                                                       rd.import_diversity,

                                                       'resource_ids',
                                                       rd.resource_ids
                                               )
                                                   ORDER BY rd.dependency_score DESC NULLS LAST
                                       )
                                FROM resource_dependency AS rd
                            ),
                            '[]'::JSONB
                    )
            ),

            'export_effectiveness',
            JSONB_BUILD_OBJECT(
                    'export_effectiveness',
                    COALESCE(
                            (
                                SELECT JSONB_AGG(
                                               JSONB_BUILD_OBJECT(
                                                       'workshop_type',
                                                       ee.workshop_type,

                                                       'product_type',
                                                       ee.product_type,

                                                       'export_ratio',
                                                       ee.export_ratio,

                                                       'avg_markup',
                                                       ee.avg_markup,

                                                       'workshop_ids',
                                                       ee.workshop_ids
                                               )
                                                   ORDER BY ee.export_ratio DESC, ee.avg_markup DESC
                                       )
                                FROM export_effectiveness AS ee
                            ),
                            '[]'::JSONB
                    )
            ),

            'trade_timeline',
            JSONB_BUILD_OBJECT(
                    'trade_growth',
                    COALESCE(
                            (
                                SELECT JSONB_AGG(
                                               JSONB_BUILD_OBJECT(
                                                       'year',
                                                       ttg.year,

                                                       'quarter',
                                                       ttg.quarter,

                                                       'quarterly_value',
                                                       ttg.quarterly_value,

                                                       'quarterly_balance',
                                                       ttg.quarterly_balance,

                                                       'trade_diversity',
                                                       ttg.trade_diversity,

                                                       'quarterly_growth_rate',
                                                       ttg.quarterly_growth_rate
                                               )
                                                   ORDER BY ttg.year, ttg.quarter
                                       )
                                FROM trade_timeline_with_growth AS ttg
                            ),
                            '[]'::JSONB
                    )
            )
    ) AS trade_analysis
FROM global_trade_stats AS gts;

--reference
WITH civilization_trade_history AS (
    SELECT
        c.civilization_type,
        EXTRACT(YEAR FROM c.arrival_date) AS trade_year,
        COUNT(DISTINCT c.caravan_id) AS caravan_count,
        SUM(tt.value) AS total_trade_value,
        SUM(CASE WHEN cg.type = 'Import' THEN cg.value ELSE 0 END) AS import_value,
        SUM(CASE WHEN cg.type = 'Export' THEN cg.value ELSE 0 END) AS export_value,
        COUNT(DISTINCT cg.goods_id) AS unique_goods_traded,
        COUNT(DISTINCT CASE WHEN cg.type = 'Import' THEN cg.goods_id END) AS unique_imports,
        COUNT(DISTINCT CASE WHEN cg.type = 'Export' THEN cg.goods_id END) AS unique_exports
    FROM
        caravans c
            JOIN
        trade_transactions tt ON c.caravan_id = tt.caravan_id
            JOIN
        caravan_goods cg ON c.caravan_id = cg.caravan_id
    GROUP BY
        c.civilization_type, EXTRACT(YEAR FROM c.arrival_date)
),
     fortress_resource_dependency AS (
         SELECT
             cg.material_type,
             COUNT(DISTINCT cg.goods_id) AS times_imported,
             SUM(cg.quantity) AS total_imported,
             SUM(cg.value) AS total_import_value,
             COUNT(DISTINCT c.caravan_id) AS caravans_importing,
             AVG(cg.price_fluctuation) AS avg_price_fluctuation,
             -- Calculate resource dependency score
             (COUNT(DISTINCT cg.goods_id) *
              SUM(cg.quantity) *
              (1.0 / NULLIF(COUNT(DISTINCT c.civilization_type), 0))
                 ) AS dependency_score
         FROM
             caravan_goods cg
                 JOIN
             caravans c ON cg.caravan_id = c.caravan_id
         WHERE
             cg.type = 'Import'
         GROUP BY
             cg.material_type
     ),
     diplomatic_trade_correlation AS (
         SELECT
             c.civilization_type,
             COUNT(DISTINCT de.event_id) AS diplomatic_events,
             COUNT(DISTINCT CASE WHEN de.outcome = 'Positive' THEN de.event_id END) AS positive_events,
             COUNT(DISTINCT CASE WHEN de.outcome = 'Negative' THEN de.event_id END) AS negative_events,
             SUM(tt.value) AS total_trade_value,
             CORR(
                     de.relationship_change,
                     tt.value
             ) AS trade_diplomacy_correlation
         FROM
             caravans c
                 JOIN
             trade_transactions tt ON c.caravan_id = tt.caravan_id
                 JOIN
             diplomatic_events de ON c.civilization_type = de.civilization_type
         GROUP BY
             c.civilization_type
     ),
     workshop_export_effectiveness AS (
         SELECT
             p.type AS product_type,
             w.type AS workshop_type,
             COUNT(DISTINCT p.product_id) AS products_created,
             COUNT(DISTINCT CASE WHEN cg.goods_id IS NOT NULL THEN p.product_id END) AS products_exported,
             SUM(p.value) AS total_production_value,
             SUM(CASE WHEN cg.goods_id IS NOT NULL THEN cg.value ELSE 0 END) AS export_value,
             AVG(CASE WHEN cg.goods_id IS NOT NULL THEN (cg.value / p.value) ELSE NULL END) AS avg_export_markup
         FROM
             products p
                 JOIN
             workshops w ON p.workshop_id = w.workshop_id
                 LEFT JOIN
             caravan_goods cg ON p.product_id = cg.original_product_id AND cg.type = 'Export'
         GROUP BY
             p.type, w.type
     ),
     trade_timeline AS (
         SELECT
             EXTRACT(YEAR FROM c.arrival_date) AS year,
    EXTRACT(QUARTER FROM c.arrival_date) AS quarter,
    SUM(tt.value) AS quarterly_trade_value,
    COUNT(DISTINCT c.civilization_type) AS trading_civilizations,
    SUM(CASE WHEN tt.balance_direction = 'Import' THEN tt.value ELSE 0 END) AS import_value,
    SUM(CASE WHEN tt.balance_direction = 'Export' THEN tt.value ELSE 0 END) AS export_value,
    LAG(SUM(tt.value)) OVER (ORDER BY EXTRACT(YEAR FROM c.arrival_date), EXTRACT(QUARTER FROM c.arrival_date)) AS previous_quarter_value
FROM
    caravans c
    JOIN
    trade_transactions tt ON c.caravan_id = tt.caravan_id
GROUP BY
    EXTRACT(YEAR FROM c.arrival_date), EXTRACT(QUARTER FROM c.arrival_date)
    )
SELECT
    -- Overall trade statistics
    (SELECT COUNT(DISTINCT civilization_type) FROM caravans) AS total_trading_partners,
    (SELECT SUM(total_trade_value) FROM civilization_trade_history) AS all_time_trade_value,
    (SELECT SUM(export_value) - SUM(import_value) FROM civilization_trade_history) AS all_time_trade_balance,

    -- Civilization breakdown with REST API format
    JSON_OBJECT(
            'civilization_trade_data', (
        SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(
                               'civilization_type', cth.civilization_type,
                               'total_caravans', SUM(cth.caravan_count),
                               'total_trade_value', SUM(cth.total_trade_value),
                               'trade_balance', SUM(cth.export_value) - SUM(cth.import_value),
                               'trade_relationship', CASE
                                                         WHEN (SUM(cth.export_value) - SUM(cth.import_value)) > 0 THEN 'Favorable'
                                                         WHEN (SUM(cth.export_value) - SUM(cth.import_value)) < 0 THEN 'Unfavorable'
                                                         ELSE 'Balanced'
                                   END,
                               'diplomatic_correlation', dtc.trade_diplomacy_correlation,
                               'unique_goods_traded', SUM(cth.unique_goods_traded),
                               'years_active', COUNT(DISTINCT cth.trade_year),
                               'caravan_ids', (
                                   SELECT JSON_ARRAYAGG(c.caravan_id)
                                   FROM caravans c
                                   WHERE c.civilization_type = cth.civilization_type
                               )
                       )
               )
        FROM civilization_trade_history cth
                 LEFT JOIN diplomatic_trade_correlation dtc ON cth.civilization_type = dtc.civilization_type
        GROUP BY cth.civilization_type, dtc.trade_diplomacy_correlation
    )
    ) AS civilization_data,

    -- Resource dependency analysis
    JSON_OBJECT(
            'resource_dependency', (
        SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(
                               'material_type', frd.material_type,
                               'dependency_score', frd.dependency_score,
                               'total_imported', frd.total_imported,
                               'import_diversity', frd.caravans_importing,
                               'price_volatility', frd.avg_price_fluctuation,
                               'resource_ids', (
                                   SELECT JSON_ARRAYAGG(DISTINCT r.resource_id)
                                   FROM resources r
                                            JOIN caravan_goods cg ON r.name = cg.material_type
                                   WHERE r.type = frd.material_type
                               )
                       )
               )
        FROM fortress_resource_dependency frd
        ORDER BY frd.dependency_score DESC
        LIMIT 10
        )
    ) AS critical_import_dependencies,

    -- Workshop export analysis
    JSON_OBJECT(
            'export_effectiveness', (
        SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(
                               'workshop_type', wee.workshop_type,
                               'product_type', wee.product_type,
                               'export_ratio', ROUND((wee.products_exported::DECIMAL / NULLIF(wee.products_created, 0)) * 100, 2),
                               'avg_markup', wee.avg_export_markup,
                               'total_export_value', wee.export_value,
                               'workshop_ids', (
                                   SELECT JSON_ARRAYAGG(w.workshop_id)
                                   FROM workshops w
                                   WHERE w.type = wee.workshop_type
                               )
                       )
               )
        FROM workshop_export_effectiveness wee
        WHERE wee.products_created > 0
        ORDER BY wee.export_value DESC
    )
    ) AS export_effectiveness,

    -- Trade growth analysis
    JSON_OBJECT(
            'trade_growth', (
        SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(
                               'year', tt.year,
                               'quarter', tt.quarter,
                               'quarterly_value', tt.quarterly_trade_value,
                               'quarterly_balance', tt.export_value - tt.import_value,
                               'growth_from_previous', CASE
                                                           WHEN tt.previous_quarter_value IS NULL THEN NULL
                                                           ELSE ROUND(((tt.quarterly_trade_value - tt.previous_quarter_value) /
                                                                       NULLIF(tt.previous_quarter_value, 0)) * 100, 2)
                                   END,
                               'trade_diversity', tt.trading_civilizations
                       )
               )
        FROM trade_timeline tt
        ORDER BY tt.year, tt.quarter
    )
    ) AS trade_timeline,

    -- Trade impact on fortress economy
    JSON_OBJECT(
            'economic_impact', (
        SELECT JSON_OBJECT(
                       'import_to_production_ratio', ROUND(
                        (SELECT SUM(import_value) FROM civilization_trade_history) /
                        NULLIF((SELECT SUM(total_production_value) FROM workshop_export_effectiveness), 0) * 100, 2
                                                     ),
                       'export_to_production_ratio', ROUND(
                               (SELECT SUM(export_value) FROM civilization_trade_history) /
                               NULLIF((SELECT SUM(total_production_value) FROM workshop_export_effectiveness), 0) * 100, 2
                                                     ),
                       'trade_dependency_score', ROUND(
                               (SELECT SUM(total_trade_value) FROM civilization_trade_history) /
                               (SELECT COUNT(DISTINCT trade_year) FROM civilization_trade_history) /
                               (SELECT SUM(p.value) FROM products p) * 100, 2
                                                 ),
                       'most_profitable_exports', (
                           SELECT JSON_ARRAYAGG(
                                          JSON_OBJECT(
                                                  'product_type', x.product_type,
                                                  'total_value', x.export_value,
                                                  'product_ids', (
                                                      SELECT JSON_ARRAYAGG(p.product_id)
                                                      FROM products p
                                                               JOIN caravan_goods cg ON p.product_id = cg.original_product_id
                                                      WHERE p.type = x.product_type AND cg.type = 'Export'
                                                      LIMIT 100
                                              )
                        )
                                  )
                           FROM (
                                    SELECT product_type, SUM(export_value) AS export_value
                                    FROM workshop_export_effectiveness
                                    GROUP BY product_type
                                    ORDER BY SUM(export_value) DESC
                                        LIMIT 5
                                ) x
                       ),
                       'most_expensive_imports', (
                           SELECT JSON_ARRAYAGG(
                                          JSON_OBJECT(
                                                  'material_type', i.material_type,
                                                  'total_value', i.import_value,
                                                  'goods_ids', (
                                                      SELECT JSON_ARRAYAGG(cg.goods_id)
                                                      FROM caravan_goods cg
                                                      WHERE cg.material_type = i.material_type AND cg.type = 'Import'
                                                      LIMIT 100
                                              )
                        )
                                  )
                           FROM (
                                    SELECT
                                        cg.material_type,
                                        SUM(cg.value) AS import_value
                                    FROM caravan_goods cg
                                    WHERE cg.type = 'Import'
                                    GROUP BY cg.material_type
                                    ORDER BY SUM(cg.value) DESC
                                        LIMIT 5
                                ) i
                       )
               )
    )
    ) AS economic_impact,

    -- Recommendations based on trade analysis
    JSON_OBJECT(
            'trade_recommendations', (
        SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(
                               'recommendation_type',
                               CASE
                                   WHEN r.dependency_score > 1000 THEN 'Critical Dependency'
                                   WHEN r.dependency_score > 500 THEN 'High Dependency'
                                   WHEN r.dependency_score > 100 THEN 'Moderate Dependency'
                                   ELSE 'Low Dependency'
                                   END,
                               'material_type', r.material_type,
                               'recommended_action',
                               CASE
                                   WHEN r.dependency_score > 1000 THEN 'Develop domestic production'
                                   WHEN r.dependency_score > 500 THEN 'Diversify import sources'
                                   WHEN r.dependency_score > 100 THEN 'Maintain strategic reserves'
                                   ELSE 'Continue current trade strategy'
                                   END,
                               'potential_partners', (
                                   SELECT JSON_ARRAYAGG(DISTINCT c.civilization_type)
                                   FROM caravans c
                                            JOIN caravan_goods cg ON c.caravan_id = cg.caravan_id
                                   WHERE cg.material_type = r.material_type AND cg.type = 'Import'
                               ),
                               'resource_ids', (
                                   SELECT JSON_ARRAYAGG(DISTINCT r2.resource_id)
                                   FROM resources r2
                                   WHERE r2.type = r.material_type
                               )
                       )
               )
        FROM fortress_resource_dependency r
        ORDER BY r.dependency_score DESC
        LIMIT 10
        ),
        'export_opportunities', (
            SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'workshop_type', w.type,
                    'current_export_ratio', COALESCE(
                        (SELECT ROUND((wee.products_exported::DECIMAL / NULLIF(wee.products_created, 0)) * 100, 2)
                         FROM workshop_export_effectiveness wee
                         WHERE wee.workshop_type = w.type
                         LIMIT 1),
                        0
                    ),
                    'potential_value', COALESCE(
                        (SELECT SUM(p.value)
                         FROM products p
                         JOIN workshops w2 ON p.workshop_id = w2.workshop_id
                         LEFT JOIN caravan_goods cg ON p.product_id = cg.original_product_id AND cg.type = 'Export'
                         WHERE w2.type = w.type AND cg.goods_id IS NULL),
                        0
                    ),
                    'recommended_civilizations', (
                        SELECT JSON_ARRAYAGG(DISTINCT c.civilization_type)
                        FROM caravans c
                        JOIN caravan_goods cg ON c.caravan_id = cg.caravan_id
                        WHERE cg.type = 'Import' AND c.civilization_type IN (
                            SELECT DISTINCT c2.civilization_type
                            FROM caravans c2
                            JOIN trade_transactions tt ON c2.caravan_id = tt.caravan_id
                            JOIN diplomatic_events de ON c2.civilization_type = de.civilization_type
                            WHERE de.outcome = 'Positive'
                        )
                    ),
                    'workshop_ids', (
                        SELECT JSON_ARRAYAGG(w2.workshop_id)
                        FROM workshops w2
                        WHERE w2.type = w.type
                    )
                )
            )
            FROM (
                SELECT DISTINCT type
                FROM workshops
            ) w
        )
    ) AS trade_recommendations
FROM (SELECT 1) AS dummy;

--reflection
-- 1. неудобное сравнение текстовых констант
-- 2. сложный контекст при объединении сгруппированных таблиц, чтобы быть уверенным в правильности, нужно много просматривать
-- предыдущие шаги, что ломает разбитие на пошаговое решение