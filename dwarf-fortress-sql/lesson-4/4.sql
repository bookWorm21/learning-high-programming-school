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
