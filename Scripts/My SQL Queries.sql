/*Monthly Merchant Statements SQL Queries*/

--Transaction Level--
WITH cte AS (
    SELECT DISTINCT 
        merchant.id AS merchant_entity_id,
        merchant.name AS merchant_name,
        app.name AS application_name,
        appGroup.name AS application_group_name,
        division.name AS division_name,
        division.id AS division_id
    FROM entity merchant
    JOIN entity app ON merchant.parent_entity_id = app.id
    JOIN entity appGroup ON app.parent_entity_id = appGroup.id
    JOIN entity division ON appGroup.parent_entity_id = division.id
    WHERE merchant.entity_type = 5
)
SELECT
    t.id,
    t.merchant_id,
    t.created_at,
    t.settled_at,
    t.currency,
    (CAST(t.amount AS FLOAT)) / 100 AS amount,
    (CAST(t.merchant_fee AS FLOAT)) / 100 AS merchant_fee,
    (CAST(t.buyer_fee AS FLOAT)) / 100 AS buyer_fee,
    ((CAST(t.merchant_fee AS FLOAT)) / 100) + ((CAST(t.buyer_fee AS FLOAT)) / 100) AS revenue,
    t.type,
    CASE
        WHEN pi.payment_method_type = 'CREDIT_CARD' OR pi.payment_method_type = 'DEBIT_CARD' THEN card_brand
        WHEN pi.payment_method_type = 'BANK_ACCOUNT' THEN 'Electronic Check'
        ELSE NULL 
    END AS card_category,
    cte.merchant_name,
    cte.division_name,
    cte.division_id,
    pi.bank_account_type,
    pi.card_brand,
    pi.payment_method_type,
    c.fee_profile_id,
    mfp.id AS mfp_id,
    mfp.created_at AS mfp_created_at,
    mp.created_at AS mp_created_at,
    TRIM(TO_CHAR(mfp.created_at - INTERVAL '1 month', 'Month')) AS StatementMonth,
    TO_CHAR(mfp.created_at - INTERVAL '1 month', 'MM - Month') AS StatementMonthSort
FROM transaction t
LEFT JOIN payment_intent pi ON t.payment_intent_id = pi.id
LEFT JOIN contract c ON pi.contract_id = c.id
JOIN cte ON cte.merchant_entity_id = t.merchant_id
INNER JOIN merchant_payout_transaction mpt ON mpt.transaction_id = t.id
LEFT JOIN merchant_payout mp ON mp.id = mpt.merchant_payout_id
LEFT JOIN merchant_fee_payout_merchant_payout mfpmp ON mfpmp.merchant_payout_id = mp.id
LEFT JOIN merchant_fee_payout mfp ON mfp.id = mfpmp.merchant_fee_payout_id
WHERE mfp.status != 'FAILED';

--Payout Level--
WITH cte AS (
    SELECT DISTINCT
        merchant.id AS merchant_entity_id,
        merchant.name AS merchant_name,
        app.name AS application_name,
        appGroup.name AS application_group_name,
        division.name AS division_name,
        division.id AS division_id
    FROM entity merchant
    JOIN entity app ON merchant.parent_entity_id = app.id
    JOIN entity appGroup ON app.parent_entity_id = appGroup.id
    JOIN entity division ON appGroup.parent_entity_id = division.id
    WHERE merchant.entity_type = 5
),
cte2 AS (
    SELECT
        date_trunc('month', mfp.created_at) AS mfp_created_at,
        mp.id AS mp_id,
        CASE
            WHEN mp.funding_type = 'GROSS' THEN SUM(mp.gross_amount / 100)
            WHEN mp.funding_type = 'NET' THEN SUM(mp.gross_amount / 100) - 
                SUM((CAST(t.merchant_fee AS FLOAT) / 100) + (CAST(t.buyer_fee AS FLOAT) / 100))
            ELSE 0
        END AS mp_amount
    FROM merchant_fee_payout mfp
    LEFT JOIN merchant_fee_payout_merchant_payout mfpmp ON mfp.id = mfpmp.merchant_fee_payout_id
    LEFT JOIN merchant_payout mp ON mfpmp.merchant_payout_id = mp.id
    LEFT JOIN merchant_payout_transaction mpt ON mp.id = mpt.merchant_payout_id
    LEFT JOIN transaction t ON mpt.transaction_id = t.id
    WHERE mfp.status != 'FAILED'
    GROUP BY date_trunc('month', mfp.created_at), mp.id, mp.funding_type
),
cte3 AS (
    SELECT
        cte.merchant_entity_id,
        cte.merchant_name,
        cte.division_name,
        cte.division_id,
        mp.id AS mp_id,
        date_trunc('month', mfp.created_at) AS mfp_created_at,
        mp.created_at AS mp_created_at,
        COUNT(DISTINCT t.id) AS txn_count,
        SUM(CAST(t.amount AS FLOAT) / 100) AS txn_volume,
        SUM(CASE WHEN t.type = 'REVERSAL' THEN 1 ELSE 0 END) AS reversal_count,
        SUM(CASE WHEN t.type = 'REVERSAL' THEN CAST(t.amount AS FLOAT) / 100 ELSE 0 END) AS reversal_amount,
        SUM(CAST(t.merchant_fee AS FLOAT) / 100) + SUM(CAST(t.buyer_fee AS FLOAT) / 100) AS fees
    FROM merchant_fee_payout mfp
    JOIN cte ON cte.merchant_entity_id = mfp.merchant_id
    LEFT JOIN merchant_fee_payout_merchant_payout mfpmp ON mfp.id = mfpmp.merchant_fee_payout_id
    LEFT JOIN merchant_payout mp ON mfpmp.merchant_payout_id = mp.id
    LEFT JOIN merchant_payout_transaction mpt ON mp.id = mpt.merchant_payout_id
    LEFT JOIN transaction t ON mpt.transaction_id = t.id
    WHERE mfp.status != 'FAILED'
    GROUP BY cte.merchant_entity_id, cte.merchant_name, cte.division_name, cte.division_id, mp.id, mfp.created_at, mp.created_at
)
SELECT
    cte3.merchant_entity_id AS merchant_id,
    cte3.merchant_name,
    cte3.division_name,
    cte3.division_id,
    cte3.mp_id,
    cte3.mfp_created_at,
    cte3.mp_created_at,
    cte3.txn_count,
    cte3.txn_volume,
    cte3.reversal_count,
    cte3.reversal_amount,
    cte3.fees,
    CAST(cte2.mp_amount / NULLIF(cte3.txn_count, 0) AS FLOAT) AS adjusted_mp_amount
FROM cte3
LEFT JOIN cte2 ON cte3.mp_id = cte2.mp_id AND cte3.mfp_created_at = cte2.mfp_created_at;

--Summary Level--
WITH cte AS (
    SELECT DISTINCT
        merchant.id AS merchant_entity_id,
        merchant.name AS merchant_name,
        app.name AS application_name,
        appGroup.name AS application_group_name,
        division.name AS division_name,
        division.id AS division_id
    FROM entity merchant
    JOIN entity app ON merchant.parent_entity_id = app.id
    JOIN entity appGroup ON app.parent_entity_id = appGroup.id
    JOIN entity division ON appGroup.parent_entity_id = division.id
    WHERE merchant.entity_type = 5
),
cte2 AS (
    SELECT
        mfp.merchant_id AS entity_id,
        date_trunc('month', mfp.created_at) AS mfp_created_at,
        date_trunc('month', mfp.created_at) - INTERVAL '1 month' AS statement_date,
        TO_CHAR(date_trunc('month', mfp.created_at) - INTERVAL '1 month', 'MM - Month') AS statement_month_sort,
        EXTRACT(YEAR FROM date_trunc('month', mfp.created_at) - INTERVAL '1 month') AS statement_year,
        CAST(SUM(COALESCE(c.amount, 0)) AS FLOAT) / 100 AS total_charges
    FROM merchant_fee_payout mfp
    LEFT JOIN merchant_fee_payout_merchant_payout mfpmp ON mfp.id = mfpmp.merchant_fee_payout_id
    LEFT JOIN merchant_payout mp ON mfpmp.merchant_payout_id = mp.id
    LEFT JOIN merchant_payout_charge mpc ON mp.id = mpc.merchant_payout_id
    LEFT JOIN charge c ON mpc.charge_id = c.id
    WHERE mfp.status != 'FAILED'
    GROUP BY mfp.merchant_id, date_trunc('month', mfp.created_at)
),
cte_txn AS (
    SELECT
        mp.id AS mp_id,
        mfp.merchant_id AS merchant_id,
        date_trunc('month', mfp.created_at) AS mfp_created_at,
        COUNT(DISTINCT t.id) AS txn_count,
        COALESCE(SUM(CAST(t.amount AS FLOAT) / 100), 0) AS gross_volume,
        COALESCE(SUM(CASE WHEN t.type = 'REVERSAL' THEN 1 ELSE 0 END), 0) AS reversal_count,
        COALESCE(SUM(CASE WHEN t.type = 'REVERSAL' THEN CAST(t.amount AS FLOAT) / 100 ELSE 0 END), 0) AS reversal_amount,
        COALESCE(SUM(CAST(t.merchant_fee AS FLOAT) / 100) + SUM(CAST(t.buyer_fee AS FLOAT) / 100), 0) AS revenue
    FROM merchant_fee_payout mfp
    LEFT JOIN merchant_fee_payout_merchant_payout mfpmp ON mfp.id = mfpmp.merchant_fee_payout_id
    LEFT JOIN merchant_payout mp ON mfpmp.merchant_payout_id = mp.id
    LEFT JOIN merchant_payout_transaction mpt ON mp.id = mpt.merchant_payout_id
    LEFT JOIN transaction t ON mpt.transaction_id = t.id
    WHERE mfp.status != 'FAILED'
    GROUP BY mp.id, mfp.merchant_id, date_trunc('month', mfp.created_at)
)
SELECT
    cte.merchant_entity_id AS merchant_id,
    cte.merchant_name,
    cte.division_name,
    cte.division_id,
    COALESCE(txn.mp_id, NULL) AS mp_id,
    COALESCE(txn.mfp_created_at, cte2.mfp_created_at) AS mfp_created_at,
    txn.txn_count,
    txn.gross_volume,
    txn.reversal_count,
    txn.reversal_amount,
    txn.revenue,
    COALESCE(cte2.total_charges, 0) AS total_charges
FROM cte
LEFT JOIN cte_txn txn ON cte.merchant_entity_id = txn.merchant_id
LEFT JOIN cte2 ON cte.merchant_entity_id = cte2.entity_id 
    AND COALESCE(txn.mfp_created_at, cte2.mfp_created_at) = cte2.mfp_created_at;

/*Financial Dashboard SQL Queries*/

--Fee Profiles--
WITH cte AS (
    SELECT DISTINCT
        merchant.id AS merchant_entity_id,
        merchant.name AS merchant_name,
        business.id AS business_id,
        business.name AS business_name,
        businessgroup.id AS business_group_id,
        businessgroup.name AS business_group_name,
        division.id AS division_id,
        division.name AS division_name
    FROM entity merchant
    JOIN entity business ON merchant.parent_entity_id = business.id
    JOIN entity businessgroup ON business.parent_entity_id = businessgroup.id
    JOIN entity division ON businessgroup.parent_entity_id = division.id
    WHERE merchant.entity_type = 5
)
SELECT
    f.id AS fee_profile_id,
    cte.*,
    m.mid,
    mfp.is_active,
    f.start_date AS "FROM",
    f.end_date AS "TO",
    CAST(JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.defaultAchFees.buyerPct')) AS DECIMAL(10,2)) / 100 AS buyerPCT,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.defaultAchFees.merchantPct')) AS DECIMAL(10,2)) / 100 AS merchantPct,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.defaultAchFees.buyerFixedFee')) AS DECIMAL(10,2)) AS buyerFixedFee,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.defaultAchFees.debitReturnFee')) AS DECIMAL(10,2)) AS debitReturnFee,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.defaultAchFees.creditReturnFee')) AS DECIMAL(10,2)) AS creditReturnFee,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.defaultAchFees.merchantFixedFee')) AS DECIMAL(10,2)) AS merchantFixedFee,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.defaultCardFees.buyerPct')) AS DECIMAL(10,2)) / 100 AS buyerPct_card,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.defaultCardFees.merchantPct')) AS DECIMAL(10,2)) / 100 AS merchantPct_card,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.defaultCardFees.buyerFixedFee')) AS DECIMAL(10,2)) AS buyerFixedFee_card,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.defaultCardFees.merchantFixedFee')) AS DECIMAL(10,2)) AS merchantFixedFee_card,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.disputeFixedFee')) AS DECIMAL(10,2)) AS disputeFixedFee,
    CASE
        WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees')) = '{}' THEN NULL
        ELSE CONCAT_WS(
            ', ',
            CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."American Express".buyerPct')) IS NOT NULL THEN 'American Express' ELSE NULL END,
            CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Visa".buyerPct')) IS NOT NULL THEN 'Visa' ELSE NULL END,
            CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."MasterCard".buyerPct')) IS NOT NULL THEN 'MasterCard' ELSE NULL END,
            CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Discover".buyerPct')) IS NOT NULL THEN 'Discover' ELSE NULL END
        )
    END AS networkSpecificFeesName,
    -- AMEX Columns
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."American Express".buyerPct')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."American Express".buyerPct')) ELSE NULL END AS DECIMAL(10,2)) / 100 AS AMEX_buyerPct,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."American Express".merchantPct')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."American Express".merchantPct')) ELSE NULL END AS DECIMAL(10,2)) / 100 AS AMEX_merchantPct,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."American Express".buyerFixedFee')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."American Express".buyerFixedFee')) ELSE NULL END AS DECIMAL(10,2)) AS AMEX_buyerFixedFee,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."American Express".merchantFixedFee')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."American Express".merchantFixedFee')) ELSE NULL END AS DECIMAL(10,2)) AS AMEX_merchantFixedFee,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."American Express".interChangePlus')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."American Express".interChangePlus')) ELSE NULL END AS CHAR) AS AMEX_interChangePlus,
    -- Visa Columns
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Visa".buyerPct')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Visa".buyerPct')) ELSE NULL END AS DECIMAL(10,2)) / 100 AS Visa_buyerPct,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Visa".merchantPct')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Visa".merchantPct')) ELSE NULL END AS DECIMAL(10,2)) / 100 AS Visa_merchantPct,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Visa".buyerFixedFee')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Visa".buyerFixedFee')) ELSE NULL END AS DECIMAL(10,2)) AS Visa_buyerFixedFee,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Visa".merchantFixedFee')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Visa".merchantFixedFee')) ELSE NULL END AS DECIMAL(10,2)) AS Visa_merchantFixedFee,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Visa".interChangePlus')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Visa".interChangePlus')) ELSE NULL END AS CHAR) AS Visa_interChangePlus,
    -- MasterCard Columns
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."MasterCard".buyerPct')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."MasterCard".buyerPct')) ELSE NULL END AS DECIMAL(10,2)) / 100 AS MasterCard_buyerPct,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."MasterCard".merchantPct')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."MasterCard".merchantPct')) ELSE NULL END AS DECIMAL(10,2)) / 100 AS MasterCard_merchantPct,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."MasterCard".buyerFixedFee')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."MasterCard".buyerFixedFee')) ELSE NULL END AS DECIMAL(10,2)) AS MasterCard_buyerFixedFee,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."MasterCard".merchantFixedFee')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."MasterCard".merchantFixedFee')) ELSE NULL END AS DECIMAL(10,2)) AS MasterCard_merchantFixedFee,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."MasterCard".interChangePlus')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."MasterCard".interChangePlus')) ELSE NULL END AS CHAR) AS MasterCard_interChangePlus,
    -- Discover Columns
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Discover".buyerPct')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Discover".buyerPct')) ELSE NULL END AS DECIMAL(10,2)) / 100 AS Discover_buyerPct,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Discover".merchantPct')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Discover".merchantPct')) ELSE NULL END AS DECIMAL(10,2)) / 100 AS Discover_merchantPct,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Discover".buyerFixedFee')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Discover".buyerFixedFee')) ELSE NULL END AS DECIMAL(10,2)) AS Discover_buyerFixedFee,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Discover".merchantFixedFee')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Discover".merchantFixedFee')) ELSE NULL END AS DECIMAL(10,2)) AS Discover_merchantFixedFee,
    CAST(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Discover".interChangePlus')) IS NOT NULL 
        THEN JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.networkSpecificFees."Discover".interChangePlus')) ELSE NULL END AS CHAR) AS Discover_interChangePlus,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.defaultInterChangePlus')) AS CHAR) AS defaultInterChangePlus,
    CAST(JSON_UNQUOTE(JSON_EXTRACT(f.configuration, '$.disputeInquiryFixedFee')) AS DECIMAL(10,2)) AS disputeInquiryFixedFee
FROM cte
LEFT JOIN merchant_fee_profile mfp ON cte.merchant_entity_id = mfp.merchant_id
LEFT JOIN merchant m ON cte.merchant_entity_id = m.id
LEFT JOIN fee_profile f ON mfp.fee_profile_id = f.id;

--Profitability--
WITH date_calendar AS (
    SELECT generate_series('2022-01-01'::date, CURRENT_DATE, '1 day'::interval)::date AS calendar_date
),
cte AS (
    SELECT
        division.id AS division_id,
        division.name AS division_name,
        t.activity_date,
        COUNT(t.id) AS transaction_count,
        SUM(CASE WHEN card_present = 'true' THEN settlement_amount ELSE 0 END) AS settlement_amount_core,
        SUM(CASE WHEN card_present = 'false' THEN settlement_amount ELSE 0 END) AS settlement_amount_vap,
        SUM(settlement_amount) AS settlement_amount,
        SUM(merchant_fee + buyer_fee) AS revenue,
        SUM(CASE WHEN card_present = 'true' THEN interchange_amount ELSE 0 END) AS interchange_core,
        SUM(CASE WHEN card_present = 'false' THEN interchange_amount ELSE 0 END) AS interchange_vap,
        SUM(interchange_amount) AS interchange_amount,
        SUM(CASE WHEN card_present = 'true' AND transaction_type = 'CREDIT' THEN interchange_amount ELSE 0 END) AS interchange_credit_card,
        SUM(CASE WHEN card_present = 'true' AND transaction_type = 'DEBIT' THEN interchange_amount ELSE 0 END) AS interchange_debit_card,
        SUM(CASE WHEN card_present = 'true' AND transaction_type = 'REVERS' THEN interchange_amount ELSE 0 END) AS reversals_core
    FROM transaction t
    INNER JOIN entity merchant ON t.merchant_entity_id = merchant.id
    JOIN entity business ON merchant.parent_entity_id = business.id
    JOIN entity businessgroup ON business.parent_entity_id = businessgroup.id
    JOIN entity division ON businessgroup.parent_entity_id = division.id
    GROUP BY t.activity_date, division.id, division.name
),
cte2 AS (
    SELECT
        mf.statement_date,
        division.id AS division_id,
        division.name AS division_name,
        SUM(CASE WHEN mf.source LIKE 'PayFac%' THEN 0 ELSE mf.amount END) AS otherfees_core,
        SUM(CASE WHEN mf.source LIKE 'PayFac%' THEN mf.amount END) AS otherfees_vap,
        SUM(mf.amount) AS otherfeesamount
    FROM merchant_fee mf
    INNER JOIN entity merchant ON mf.merchant_entity_id = merchant.id
    JOIN entity business ON merchant.parent_entity_id = business.id
    JOIN entity businessgroup ON business.parent_entity_id = businessgroup.id
    JOIN entity division ON businessgroup.parent_entity_id = division.id
    WHERE (mf.fee_category <> 5 OR (mf.fee_category = 5 AND NOT mf.source LIKE 'PayFac%'))
    GROUP BY mf.statement_date, division.id, division.name
)
SELECT
    COALESCE(cte.division_id, cte2.division_id) AS division_id,
    COALESCE(cte.division_name, cte2.division_name) AS division_name,
    COALESCE(SUM(cte.transaction_count), 0) AS transaction_count,
    dc.calendar_date AS activity_date,
    COALESCE(SUM(cte.settlement_amount_core), 0) AS settlement_amount_core,
    COALESCE(SUM(cte.settlement_amount_vap), 0) AS settlement_amount_vap,
    COALESCE(SUM(cte.settlement_amount), 0) AS settlement_amount,
    COALESCE(SUM(cte.revenue), 0) AS revenue,
    COALESCE(SUM(cte2.otherfees_core), 0) AS otherfees_core,
    COALESCE(SUM(cte2.otherfees_vap), 0) AS otherfees_vap,
    COALESCE(SUM(cte2.otherfeesamount), 0) AS otherfeesamount,
    COALESCE(SUM(cte.interchange_core), 0) AS interchange_core,
    COALESCE(SUM(cte.interchange_vap), 0) AS interchange_vap,
    COALESCE(SUM(cte.interchange_amount), 0) AS interchange_amount,
    COALESCE(SUM(cte.interchange_credit_card), 0) AS interchange_credit_card,
    COALESCE(SUM(cte.interchange_debit_card), 0) AS interchange_debit_card,
    COALESCE(SUM(cte.reversals_core), 0) AS reversals_core
FROM date_calendar dc
LEFT JOIN cte ON dc.calendar_date = cte.activity_date
LEFT JOIN cte2 ON dc.calendar_date = cte2.statement_date
    AND COALESCE(cte.division_id, cte2.division_id) = cte2.division_id
    AND COALESCE(cte.division_name, cte2.division_name) = cte2.division_name
GROUP BY dc.calendar_date, COALESCE(cte.division_id, cte2.division_id), COALESCE(cte.division_name, cte2.division_name)
ORDER BY dc.calendar_date;

--Transaction--
WITH cte AS (
    SELECT DISTINCT 
        merchant.id AS merchant_entity_id,
        merchant.name AS merchant_name,
        business.id AS business_id,
        business.name AS business_name,
        businessgroup.id AS business_group_id,
        businessgroup.name AS business_group_name,
        division.id AS division_id,
        division.name AS division_name
    FROM entity merchant
    JOIN entity business ON merchant.parent_entity_id = business.id
    JOIN entity businessgroup ON business.parent_entity_id = businessgroup.id
    JOIN entity division ON businessgroup.parent_entity_id = division.id
    WHERE merchant.entity_type = 5
)
SELECT
    t.id,
    t.payment_intent_id,
    t.payment_method_id,
    t.merchant_id,
    t.mid,
    t.currency,
    NULL AS Description,
    (CAST(t.amount AS FLOAT) / 100) AS Amount,
    (CAST(t.buyer_fee AS FLOAT) / 100) AS buyer_fee,
    (CAST(t.merchant_fee AS FLOAT) / 100) AS merchant_fee,
    (CAST(t.buyer_fee AS FLOAT) / 100) + (CAST(t.merchant_fee AS FLOAT) / 100) AS Revenue,
    t.type,
    t.status,
    t.payment_method_type,
    t.funding_status,
    t.created_at,
    CAST(EXTRACT(YEAR FROM t.created_at) AS INT) AS year,
    TO_CHAR(t.created_at, 'MM - Month') AS month_name,
    CAST(EXTRACT(MONTH FROM t.created_at) AS INT) AS month,
    EXTRACT(DAY FROM t.created_at) AS day,
    EXTRACT(QUARTER FROM t.created_at) AS quarter,
    EXTRACT(WEEK FROM t.created_at) AS week,
    TO_CHAR(t.created_at, 'MM-DD-YYYY') || ' - ' || TO_CHAR(t.created_at, 'Day') AS day_of_week_date,
    DATE_TRUNC('month', t.created_at) AS first_day_of_month,
    DATE_TRUNC('quarter', t.created_at) AS first_day_of_quarter,
    DATE_TRUNC('year', t.created_at) AS first_day_of_year,
    t.settled_at,
    t.can_be_paid,
    t.funded_at,
    t.network_transaction_id,
    t.original_transaction_id,
    (CAST(mp.gross_amount AS FLOAT) / 100) AS mp_amount,
    mp.created_at AS mp_created_at,
    (CAST(mfp.amount AS FLOAT) / 100) AS mfp_amount,
    TO_CHAR(mfp.created_at - INTERVAL '1 month', 'MM - Month') AS StatementMonth,
    cte.merchant_name,
    cte.merchant_entity_id,
    cte.business_name,
    cte.business_id,
    cte.business_group_name,
    cte.business_group_id,
    cte.division_name,
    cte.division_id
FROM transaction t
LEFT JOIN cte ON cte.merchant_entity_id = t.merchant_id
LEFT JOIN merchant_payout_transaction mpt ON mpt.transaction_id = t.id
LEFT JOIN merchant_payout mp ON mp.id = mpt.merchant_payout_id
LEFT JOIN merchant_fee_payout_merchant_payout mfpmp ON mfpmp.merchant_payout_id = mp.id
LEFT JOIN merchant_fee_payout mfp ON mfp.id = mfpmp.merchant_fee_payout_id
WHERE cte.merchant_entity_id NOT IN (
    'MERCHANT_ID_1', 'MERCHANT_ID_2', 'MERCHANT_ID_3', 'MERCHANT_ID_4', 'MERCHANT_ID_5', 
    'MERCHANT_ID_6', 'MERCHANT_ID_7', 'MERCHANT_ID_8', 'MERCHANT_ID_9', 'MERCHANT_ID_10',
    'MERCHANT_ID_11', 'MERCHANT_ID_12', 'MERCHANT_ID_13', 'MERCHANT_ID_14', 'MERCHANT_ID_15',
    'MERCHANT_ID_16', 'MERCHANT_ID_17', 'MERCHANT_ID_18', 'MERCHANT_ID_19', 'MERCHANT_ID_20',
    'MERCHANT_ID_21', 'MERCHANT_ID_22', 'MERCHANT_ID_23', 'MERCHANT_ID_24', 'MERCHANT_ID_25',
    'MERCHANT_ID_26', 'MERCHANT_ID_27', 'MERCHANT_ID_28', 'MERCHANT_ID_29', 'MERCHANT_ID_30',
    'MERCHANT_ID_31', 'MERCHANT_ID_32', 'MERCHANT_ID_33', 'MERCHANT_ID_34', 'MERCHANT_ID_35',
    'MERCHANT_ID_36', 'MERCHANT_ID_37', 'MERCHANT_ID_38', 'MERCHANT_ID_39', 'MERCHANT_ID_40',
    'MERCHANT_ID_41', 'MERCHANT_ID_42', 'MERCHANT_ID_43', 'MERCHANT_ID_44', 'MERCHANT_ID_45',
    'MERCHANT_ID_46', 'MERCHANT_ID_47', 'MERCHANT_ID_48', 'MERCHANT_ID_49'
)
UNION ALL
SELECT
    c.id,
    NULL AS payment_intent_id,
    NULL AS payment_method_id,
    c.entity_id AS merchant_id,
    NULL AS mid,
    NULL AS currency,
    c.Description,
    NULL AS Amount,
    NULL AS buyer_fee,
    NULL AS merchant_fee,
    (CAST(c.amount AS FLOAT) / 100) AS Revenue,
    c.type,
    NULL AS status,
    NULL AS payment_method_type,
    c.funding_status,
    c.created_at,
    CAST(EXTRACT(YEAR FROM c.created_at) AS INT) AS year,
    TO_CHAR(c.created_at, 'MM - Month') AS month_name,
    CAST(EXTRACT(MONTH FROM c.created_at) AS INT) AS month,
    EXTRACT(DAY FROM c.created_at) AS day,
    EXTRACT(QUARTER FROM c.created_at) AS quarter,
    EXTRACT(WEEK FROM c.created_at) AS week,
    TO_CHAR(c.created_at, 'MM-DD-YYYY') || ' - ' || TO_CHAR(c.created_at, 'Day') AS day_of_week_date,
    DATE_TRUNC('month', c.created_at) AS first_day_of_month,
    DATE_TRUNC('quarter', c.created_at) AS first_day_of_quarter,
    DATE_TRUNC('year', c.created_at) AS first_day_of_year,
    NULL AS settled_at,
    NULL AS can_be_paid,
    c.funded_at,
    NULL AS network_transaction_id,
    NULL AS original_transaction_id,
    NULL AS mp_amount,
    NULL AS mp_created_at,
    NULL AS mfp_amount,
    NULL AS StatementMonth,
    cte.merchant_name,
    cte.merchant_entity_id,
    cte.business_name,
    cte.business_id,
    cte.business_group_name,
    cte.business_group_id,
    cte.division_name,
    cte.division_id
FROM charge c
LEFT JOIN cte ON cte.merchant_entity_id = c.entity_id
LEFT JOIN merchant_payout_charge mpc ON c.id = mpc.charge_id
LEFT JOIN merchant_payout mp ON mpc.merchant_payout_id = mp.id
LEFT JOIN merchant_fee_payout_merchant_payout mfpmp ON mp.id = mfpmp.merchant_payout_id
LEFT JOIN merchant_fee_payout mfp ON mfpmp.merchant_fee_payout_id = mfp.id
WHERE c.created_at > '2024-08-01'
ORDER BY created_at;

--Operating Account--
WITH revenue_cte AS (
    SELECT
        division.id AS division_id,
        division.name AS division_name,
        t.activity_date AS ledger_date,
        SUM(merchant_fee + buyer_fee) AS daily_revenue
    FROM transaction t
    INNER JOIN entity merchant ON t.merchant_entity_id = merchant.id
    JOIN entity business ON merchant.parent_entity_id = business.id
    JOIN entity businessgroup ON business.parent_entity_id = businessgroup.id
    JOIN entity division ON businessgroup.parent_entity_id = division.id
    WHERE division.id IN (
        'DIVISION_ID_1', 'DIVISION_ID_2', 'DIVISION_ID_3', 'DIVISION_ID_4', 
        'DIVISION_ID_5', 'DIVISION_ID_6', 'DIVISION_ID_7', 'DIVISION_ID_8', 
        'DIVISION_ID_9'
    )
    GROUP BY division.id, division.name, t.activity_date
),
cte AS (
    SELECT
        division.id AS division_id,
        division.name AS division_name,
        CASE
            WHEN card_present = 'true' AND transaction_type = 'CREDIT' THEN t.activity_date + INTERVAL '1 day'
            WHEN card_present = 'true' AND transaction_type = 'DEBIT' THEN t.activity_date + INTERVAL '1 day'
            WHEN card_present = 'false' THEN t.activity_date + INTERVAL '2 days'
            WHEN transaction_type = 'REVERS' THEN t.activity_date
            ELSE t.activity_date
        END AS ledger_date,
        CASE
            WHEN card_present = 'true' AND transaction_type = 'CREDIT' THEN 'interchange_credit_card'
            WHEN card_present = 'true' AND transaction_type = 'DEBIT' THEN 'interchange_debit_card'
            WHEN card_present = 'false' THEN 'ac_vantiv_ecomm'
            WHEN transaction_type = 'REVERS' THEN 'reversals_core'
            ELSE NULL
        END AS Reference_Text,
        CASE
            WHEN transaction_type = 'REVERS' THEN settlement_amount
            ELSE interchange_amount
        END AS cost,
        0 AS revenue
    FROM transaction t
    INNER JOIN entity merchant ON t.merchant_entity_id = merchant.id
    JOIN entity business ON merchant.parent_entity_id = business.id
    JOIN entity businessgroup ON business.parent_entity_id = businessgroup.id
    JOIN entity division ON businessgroup.parent_entity_id = division.id
    WHERE division.id IN (
        'DIVISION_ID_1', 'DIVISION_ID_2', 'DIVISION_ID_3', 'DIVISION_ID_4', 
        'DIVISION_ID_5', 'DIVISION_ID_6', 'DIVISION_ID_7', 'DIVISION_ID_8', 
        'DIVISION_ID_9'
    )
),
cte2 AS (
    SELECT
        division.id AS division_id,
        division.name AS division_name,
        CASE
            WHEN mf.source LIKE 'PayFac%' THEN mf.statement_date + INTERVAL '2 days'
            ELSE mf.statement_date + INTERVAL '10 days'
        END AS ledger_date,
        CASE
            WHEN mf.source LIKE 'PayFac%' THEN 'ac_vantiv_ecomm'
            ELSE 'otherfees_core'
        END AS Reference_Text,
        -mf.amount AS cost,
        0 AS revenue
    FROM merchant_fee mf
    JOIN entity merchant ON mf.merchant_entity_id = merchant.id
    JOIN entity business ON merchant.parent_entity_id = business.id
    JOIN entity businessgroup ON business.parent_entity_id = businessgroup.id
    JOIN entity division ON businessgroup.parent_entity_id = division.id
    WHERE (mf.fee_category <> 5 OR (mf.fee_category = 5 AND NOT mf.source LIKE 'PayFac%'))
    AND division.id IN (
        'DIVISION_ID_1', 'DIVISION_ID_2', 'DIVISION_ID_3', 'DIVISION_ID_4', 
        'DIVISION_ID_5', 'DIVISION_ID_6', 'DIVISION_ID_7', 'DIVISION_ID_8', 
        'DIVISION_ID_9'
    )
),
combined AS (
    SELECT * FROM cte
    UNION ALL
    SELECT * FROM cte2
),
aggregated AS (
    SELECT
        division_id,
        division_name,
        ledger_date,
        Reference_Text,
        SUM(cost) AS costs,
        0 AS revenue
    FROM combined
    WHERE Reference_Text <> 'revenue'
    GROUP BY division_id, division_name, ledger_date, Reference_Text
    UNION ALL
    SELECT
        r.division_id,
        r.division_name,
        r.ledger_date,
        'revenue' AS Reference_Text,
        0 AS costs,
        r.daily_revenue AS revenue
    FROM revenue_cte r
)
SELECT *,
    CASE
        WHEN division_id = 'DIVISION_ID_2' THEN 'VSI ODIN Operating Account'
        WHEN division_id = 'DIVISION_ID_9' THEN 'VSI ODIN Operating Account'
        WHEN division_id = 'DIVISION_ID_6' THEN 'VSI ODIN Operating Account'
        WHEN division_id = 'DIVISION_ID_X' THEN 'VSI Finix Operating Account'
        WHEN division_id = 'DIVISION_ID_Y' THEN 'ForeUp Finix Operating Account'
        WHEN division_id = 'DIVISION_ID_4' THEN 'ForeUp ODIN Operating Account'
        WHEN division_id = 'DIVISION_ID_7' THEN 'Clubessential ODIN Operating Account'
        WHEN division_id = 'DIVISION_ID_Z' THEN 'Clubessential Finix Operating Account'
        WHEN division_id = 'DIVISION_ID_3' THEN 'Canada Operating Account'
        ELSE 'Other'
    END AS operating_acct
FROM aggregated
ORDER BY ledger_date, division_id, Reference_Text;

/*PowerBi, Merchant Processing, and SSRS Reprt Queries*/

--Merchant Processing View--
SELECT Month, CLUB, isXPO, Value, Amount
FROM (
    SELECT Month, CLUB, isXPO, '03_WP - Credit Card (Visa,MC,Dis)-Total Network Costs' AS Value, 
           SUM(CAST(Total_Fees AS DECIMAL(18, 2))) AS Amount
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (NOT (Fee_Category_Type = 'Vantiv Fees')) 
          AND (NOT (Fee_Category = 'Revenue Solutions')) AND (NOT (Payment_Type = 'Electronic Check')) 
          AND (NOT (Payment_Type = 'American Express')) AND (NOT (Fee_Category = 'Assessments')) 
          AND (NOT (Description LIKE '%DEBIT%'))
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '04_Intermediate - CC and Debit Gateway Fees' AS Value, 
           SUM(CAST(Total_Fees AS DECIMAL(18, 2))) AS Amount
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (Fee_Category_Type = 'Vantiv Fees') 
          AND (NOT (Fee_Sub_Category = 'Chargebacks/Returns')) AND (NOT (Fee_Category = 'Revenue Solutions')) 
          AND (NOT (Payment_Type IN ('Electronic Check', 'American Express')))
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '06_WP - Credit Card (Visa,MC,Dis)-Assesments' AS Value, 
           SUM(CAST(Total_Fees AS DECIMAL(18, 2))) AS Amount
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (NOT (Fee_Category_Type = 'Vantiv Fees')) 
          AND (NOT (Fee_Category = 'Revenue Solutions')) AND (NOT (Payment_Type = 'Electronic Check')) 
          AND (NOT (Payment_Type = 'American Express')) AND (Fee_Category = 'Assessments') 
          AND (NOT (Description LIKE '%DEBIT%'))
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '08_WP - Credit Cards (AMEX) - Total Network Costs' AS payment_type, 
           SUM(CAST(Total_Fees AS DECIMAL(18, 2))) AS Value
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (Payment_Type = 'American Express') AND (NOT (Fee_Category_Type = 'Vantiv Fees')) 
          AND (NOT (Fee_Category IN ('Assessments', 'Authorizations')))
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, 'American Express OptBlue Assesment' AS Value, 
           SUM(CAST(Total_Fees AS DECIMAL(18, 2))) AS Amount
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (Description LIKE '%INT AMEX OptBlue%')
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '09_WP - Credit Cards (AMEX) - Total Gateway Costs' AS Value, 
           SUM(CAST(Total_Fees AS DECIMAL(18, 2))) AS Amount
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (Fee_Category_Type = 'Vantiv Fees') 
          AND (NOT (Fee_Sub_Category = 'Chargebacks/Returns')) AND (NOT (Fee_Category = 'Revenue Solutions')) 
          AND (Payment_Type = 'American Express')
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '10_WP - Credit Cards (AMEX) - Brand Assesments' AS payment_type, 
           SUM(CAST(Total_Fees AS DECIMAL(18, 2))) AS Value
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (Payment_Type = 'American Express') AND (NOT (Fee_Category_Type = 'Vantiv Fees')) 
          AND (Fee_Category = 'Assessments')
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '16_WP - Regulated DEBIT Cards - Total Interchange Costs' AS payment_type, 
           SUM(CAST(Total_Fees AS DECIMAL(18, 2))) AS Value
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (reporting_group = 'REPORTING_GROUP_X') AND (NOT (Payment_Type = 'Not Applicable')) 
          AND (NOT (Fee_Category_Type = 'Vantiv Fees')) AND (Description LIKE '%DEBIT%') 
          AND (Description LIKE '%Regulated%') AND (NOT (Fee_Category IN ('Assessments', 'Authorizations')))
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '20_WP - UnRegulated DEBIT Cards - Total Interchange Costs' AS payment_type, 
           SUM(CAST(Total_Fees AS DECIMAL(18, 2))) AS Value
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (reporting_group = 'REPORTING_GROUP_X') AND (NOT (Payment_Type = 'Not Applicable')) 
          AND (NOT (Fee_Category_Type = 'Vantiv Fees')) AND (Description LIKE '%DEBIT%') 
          AND (NOT (Description LIKE '%Regulated%')) AND (NOT (Fee_Category IN ('Assessments', 'Authorizations')))
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '13_WP - Combined DEBIT Cards Assesments' AS payment_type, 
           SUM(CAST(Total_Fees AS DECIMAL(18, 2))) AS Value
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (NOT (Fee_Category_Type = 'Vantiv Fees')) 
          AND (Description LIKE '%DEBIT%') AND (NOT (Description LIKE '%Regulated%')) 
          AND (Fee_Category = 'Assessments')
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '14_WP - Combined DEBIT Cards Authorizations' AS payment_type, 
           SUM(CAST(Total_Fees AS DECIMAL(18, 2))) AS Value
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (NOT (Fee_Category_Type = 'Vantiv Fees')) 
          AND (Description LIKE '%DEBIT%') AND (NOT (Description LIKE '%Regulated%')) 
          AND (Fee_Category = 'Authorizations')
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '24_WP - eCheck - Total Gateway Costs' AS payment_type, 
           SUM(CAST(Total_Fees AS DECIMAL(18, 2))) AS Value
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (Fee_Category_Type = 'Vantiv Fees') AND (Payment_Type = 'Electronic Check') 
          AND (Fee_Category = 'Payments Acceptance')
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '26_WP - Account Updater Costs' AS Value, 
           SUM(CAST(Total_Fees AS DECIMAL(18, 2))) AS Amount
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (NOT (Fee_Category LIKE '%DEBIT%')) 
          AND (Fee_Category_Type = 'Vantiv Fees') AND (Fee_Category = 'Revenue Solutions')
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '27_WP - Chargeback Costs' AS Value, 
           SUM(CAST(Total_Fees AS DECIMAL(18, 2))) AS Amount
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (NOT (Fee_Category LIKE '%DEBIT%')) 
          AND (Fee_Category_Type = 'Vantiv Fees') AND (Fee_Sub_Category = 'Chargebacks/Returns')
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '30_WP - Credit Card Counts (Visa,MC,Dis)' AS Value, 
           SUM(CAST(Txn_Count AS INT)) AS Amount
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (NOT (Fee_Category_Type = 'Vantiv Fees')) 
          AND (NOT (Fee_Category = 'Revenue Solutions')) AND (NOT (Payment_Type = 'Electronic Check')) 
          AND (NOT (Payment_Type = 'American Express')) AND (NOT (Fee_Category IN ('Assessments', 'Credit Interchange'))) 
          AND (NOT (Description LIKE '%DEBIT%')) AND (NOT (Description LIKE '%AVS%'))
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '31_WP - Credit Card Counts (AMEX)' AS Value, 
           SUM(CAST(Txn_Count AS INT)) AS Amount
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (Fee_Category_Type = 'Vantiv Fees') 
          AND (NOT (Fee_Category = 'Revenue Solutions')) AND (Payment_Type = 'American Express')
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '32_WP - UnRegulated Debit Card Counts' AS payment_type, 
           SUM(CAST(Txn_Count AS INT)) AS Value
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (reporting_group = 'REPORTING_GROUP_X') AND (NOT (Payment_Type = 'Not Applicable')) 
          AND (NOT (Fee_Category_Type = 'Vantiv Fees')) AND (Description LIKE '%DEBIT%') 
          AND (NOT (Description LIKE '%Regulated%')) AND (NOT (Fee_Category IN ('Assessments', 'Authorizations')))
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '33_WP - Regulated Debit Card Counts' AS payment_type, 
           SUM(CAST(Txn_Count AS INT)) AS Value
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (NOT (Fee_Category_Type = 'Vantiv Fees')) 
          AND (Description LIKE '%DEBIT%') AND (Description LIKE '%Regulated%') 
          AND (NOT (Fee_Category IN ('Assessments', 'Authorizations')))
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '37_WP - Credit Card $$$ (AMEX)' AS Value, 
           SUM(CAST(Txn_Amount AS DECIMAL(18, 2))) AS Amount
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (Fee_Category_Type = 'Vantiv Fees') 
          AND (NOT (Fee_Category = 'Revenue Solutions')) AND (Payment_Type = 'American Express')
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '39_WP - Regulated Debit Card' AS payment_type, 
           SUM(CAST(Txn_Amount AS DECIMAL(18, 2))) AS Value
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (NOT (Fee_Category_Type = 'Vantiv Fees')) 
          AND (Description LIKE '%DEBIT%') AND (Description LIKE '%Regulated%') 
          AND (NOT (Fee_Category IN ('Assessments', 'Authorizations')))
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '40_WP - eCheck' AS payment_type, 
           SUM(CAST(Txn_Amount AS DECIMAL(18, 2))) AS Value
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (Fee_Category_Type = 'Vantiv Fees') AND (Payment_Type = 'Electronic Check') 
          AND (Fee_Category = 'Payments Acceptance')
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '34_WP - eCheck Counts' AS payment_type, 
           SUM(CAST(Txn_Count AS INT)) AS Value
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (Fee_Category_Type = 'Vantiv Fees') AND (Payment_Type = 'Electronic Check') 
          AND (Fee_Category = 'Payments Acceptance')
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '36_WP - Credit Card (Visa,MC,Dis)' AS Value, 
           SUM(CAST(Txn_Amount AS DECIMAL(18, 2))) AS Amount
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (NOT (Fee_Category_Type = 'Vantiv Fees')) 
          AND (NOT (Fee_Category = 'Revenue Solutions')) AND (NOT (Payment_Type = 'Electronic Check')) 
          AND (NOT (Payment_Type = 'American Express')) AND (Fee_Category = 'Credit Interchange') 
          AND (NOT (Description LIKE '%DEBIT%'))
    GROUP BY Month, CLUB, isXPO
    UNION ALL
    SELECT Month, CLUB, isXPO, '38_WP - UnRegulated Debit Card' AS payment_type, 
           SUM(CAST(Txn_Amount AS DECIMAL(18, 2))) AS Value
    FROM dbo.CA_SplitOnBrands AS RPT
    WHERE (NOT (Payment_Type = 'Not Applicable')) AND (NOT (Fee_Category_Type = 'Vantiv Fees')) 
          AND (Description LIKE '%DEBIT%') AND (NOT (Description LIKE '%Regulated%')) 
          AND (NOT (Fee_Category IN ('Assessments', 'Authorizations')))
    GROUP BY Month, CLUB, isXPO
) AS TBL;

--Management Financials: PPR--
USE [Reports]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [ssrs].[ManagementFinancials_FullService]
    @RemitGroup VARCHAR(MAX),
    @BrandId VARCHAR(MAX),
    @ChainId INT,
    @StoreId INT,
    @StartDate DATETIME,
    @EndDate DATETIME,
    @StoreStatus VARCHAR(50),
    @OnlyRemitClubs BIT,
    @Canada INT,
    @ClubState VARCHAR(MAX),
    @Period INT,
    @TransactionColumns VARCHAR(100),
    @SiteType VARCHAR(50),
    @HasNegAccrual INT = NULL,
    @GroupBy INT,
    @HideDetailColumns INT /*Set to 1 if only Net totals need to show. 1 for detail and brand summary, optional on other tabs.*/
    @HideClubCount INT /*Set to 1 for speeding up report*/,
    @NoNet INT /*Set to 1 for Mgmt Fin - Detail report*/,
    @Detail INT /*Set to 1 for product/market penetration reporting (custom requests, not detail report)*/,
    @MonthEndExport BIT = 0
AS 
/*
DECLARE
    @RemitGroup VARCHAR(MAX) = '0',
    @BrandId VARCHAR(MAX) = NULL,
    @ChainId INT = CHAIN_ID_X,
    @StoreId INT = NULL,
    @StartDate DATETIME = '9/1/2024',
    @EndDate DATETIME = '9/24/2024',
    @StoreStatus VARCHAR(50) = '0',
    @OnlyRemitClubs BIT = 0,
    @Period INT = 2,
    @Canada INT = NULL,
    @ClubState VARCHAR(MAX) = 'QQ',
    @TransactionColumns VARCHAR(100) = 'none',
    @SiteType VARCHAR(50) = NULL,
    @HasNegAccrual INT = NULL,
    @GroupBy INT = 3,
    @HideDetailColumns INT = NULL,
    @HideClubCount INT = 1,
    @NoNet INT = 1,
    @Detail INT = 1,
    @MonthEndExport BIT = 1;
*/

SET NOCOUNT ON;

SET @EndDate = DATEADD(DAY, 1, @EndDate);

DECLARE @NegAccrualCutoff DATE = CAST(GETDATE() AS DATE);
IF @HasNegAccrual = 2
BEGIN
    SET @NegAccrualCutoff = CAST(@EndDate AS DATE);
END;

IF OBJECT_ID('tempdb..#stores') IS NOT NULL
    DROP TABLE #stores;
IF OBJECT_ID('tempdb..#transactions') IS NOT NULL
    DROP TABLE #transactions;
IF OBJECT_ID('tempdb..#detail') IS NOT NULL
    DROP TABLE #detail;
IF OBJECT_ID('tempdb..#dates') IS NOT NULL
    DROP TABLE #dates;
IF OBJECT_ID('tempdb..#results') IS NOT NULL
    DROP TABLE #results;
IF OBJECT_ID('tempdb..#net') IS NOT NULL
    DROP TABLE #net;

CREATE TABLE #stores
(
    ChainId INT,
    ChainIdRebates INT,
    ChainName VARCHAR(255),
    BrandName VARCHAR(255),
    StoreId INT,
    LocationName VARCHAR(255),
    ClubCountry VARCHAR(255),
    ClubState VARCHAR(50),
    [Status] INT,
    StoreStatus VARCHAR(10),
    SiteType VARCHAR(50),
    TimeOffset INT,
    RemitGroup VARCHAR(255),
    CasCompanyId INT,
    IsRemitGroupEnabled BIT,
    IsRemitClubEnabled BIT,
    CollectionsBy INT,
    AccrualBalance DECIMAL(17, 2),
    Deleted INT,
    SiteTypeId INT,
    BillingType VARCHAR(3),
    [Address] VARCHAR(500),
    [State] VARCHAR(50)
);

DECLARE @RemitGroupUse VARCHAR(MAX) = @RemitGroup;

IF @BrandId IS NULL
BEGIN
    /*Set @RemitGroupUse to all remit groups if 0 is passed*/
    IF @RemitGroup = '0'
    BEGIN
        SET @RemitGroupUse = NULL;

        IF OBJECT_ID('tempdb..#all') IS NOT NULL
            DROP TABLE #all;

        CREATE TABLE #all
        (
            CASCompanyId VARCHAR(MAX),
            OrderBy DECIMAL(17, 2)
        );

        INSERT INTO #all
        SELECT CASCompanyId = CAST(CASCompanyID AS VARCHAR(10)),
               OrderBy = ROW_NUMBER() OVER (ORDER BY CompanyName)
        FROM ClubReady.dbo.CasCompanies;

        INSERT INTO #all
        SELECT 'REM_GROUP_1', OrderBy = .5; -- DIY Clubs
        INSERT INTO #all
        SELECT 'REM_GROUP_2', OrderBy = .4; -- PIQ Billing Hub
        INSERT INTO #all
        SELECT 'REM_GROUP_3', OrderBy = .3; -- Aurora Billing Hub
        INSERT INTO #all
        SELECT 'REM_GROUP_4', OrderBy = .2; -- iKizmet Billing Hub

        SELECT @RemitGroupUse = COALESCE(@RemitGroupUse + ',', '') + CAST(CASCompanyId AS VARCHAR(10))
        FROM #all;
    END;

    INSERT INTO #stores
    SELECT
        s.ChainID,
        ChainIdRebates = CASE
            WHEN s.ChainID IS NULL OR s.ChainID = CHAIN_ID_X THEN
                CASE
                    WHEN gp.LocationName LIKE 'BRAND_A%' AND gp.clubcountry = 'US' THEN REBATE_ID_1
                    WHEN gp.LocationName LIKE 'BRAND_B%' AND gp.clubcountry = 'US' THEN REBATE_ID_2
-----
                    WHEN gp.LocationName LIKE 'BRAND_Q%' AND gp.clubcountry = 'CA' THEN REBATE_ID_23
                END
            ELSE s.ChainID
        END,
        c.ChainName,
        BrandName = CASE
            WHEN gp.LocationName LIKE 'BRAND_D%' THEN 'BRAND_D'
            WHEN gp.LocationName LIKE 'BRAND_R%' OR c.ChainName LIKE 'BRAND_S%' THEN 'BRAND_S'
-----
            WHEN gp.LocationName LIKE 'BRAND_P%' THEN 'BRAND_P'
            ELSE ISNULL(c.ChainName, 'No Brand Assigned')
        END,
        s.StoreID,
        LocationName = gp.LocationName + CASE WHEN s.Deleted = 1 THEN ' (Deleted)' ELSE '' END,
        gp.clubcountry,
        gp.ClubState,
        s.[Status],
        StoreStatus = ss.[Name],
        SiteType = ISNULL(st.[Name], '-'),
        gp.TimeOffset,
        RemitGroup = ISNULL(co.CompanyName, 'DIY'),
        co.CASCompanyID,
        co.IsRemitGroupEnabled,
        cl.IsRemitClubEnabled,
        s.CollectionsBy,
        AccrualBalance = CAST(NULL AS DECIMAL(17, 2)),
        s.Deleted,
        b.SiteTypeId,
        BillingType = CASE WHEN cl.CasClubId IS NOT NULL THEN 'FS' ELSE 'DIY' END,
        [Address] = TRIM(ISNULL(gp.ClubAddress, '')) + ' ' + TRIM(ISNULL(gp.ClubCity, '')) + 
                    CASE WHEN ISNULL(gp.ClubState, '') = '' THEN ' ' ELSE ', ' END + 
                    TRIM(ISNULL(gp.ClubState, '')) + ' ' + TRIM(ISNULL(gp.ClubZip, '')),
        [State] = TRIM(ISNULL(
            CASE
                WHEN ClubState = 'Kentucky' THEN 'KY'
                WHEN ClubState = 'Massachusetts' THEN 'MA'
                WHEN ClubState = 'Texas' THEN 'TX'
                WHEN ClubState = 'Fl' THEN 'FL'
   --------
                ELSE ClubState
            END, ''))
    FROM ClubReady.dbo.Stores s WITH (NOLOCK)
    LEFT JOIN ClubReady.dbo.GeneralPrefs gp WITH (NOLOCK) ON s.StoreID = gp.StoreID
    LEFT JOIN ClubReady.enum.StoreStatus ss WITH (NOLOCK) ON s.[Status] = ss.StoreStatusId
    LEFT JOIN ClubReady.dbo.Chains c WITH (NOLOCK) ON s.ChainID = c.ChainID
    LEFT JOIN ClubReady.dbo.CasClubs cl WITH (NOLOCK) ON s.StoreID = cl.StoreID
    LEFT JOIN ClubReady.dbo.CasCompanies co WITH (NOLOCK) ON cl.CasCompanyID = co.CASCompanyID
    LEFT JOIN ClubReady.dbo.StoreInfoBackOffice b WITH (NOLOCK) ON s.StoreID = b.StoreId
    LEFT JOIN ClubReady.dbo.SiteType st WITH (NOLOCK) ON b.SiteTypeId = st.SiteTypeId
    WHERE (
        @RemitGroupUse IS NULL
        OR (
            @RemitGroupUse = 'REM_GROUP_X'
            AND cl.CasCompanyID IS NOT NULL
        )
        OR ISNULL(co.CASCompanyID, REM_GROUP_DEFAULT) IN (SELECT Value FROM Reports.ssrs.ParameterSplit(@RemitGroupUse, ','))
        OR @StoreId IS NOT NULL
        OR @ChainId IS NOT NULL
    )
    AND (@ChainId IS NULL OR s.ChainID = @ChainId)
    AND (@StoreId IS NULL OR s.StoreID = @StoreId)
    AND (
        (@StoreStatus = '0' AND s.[Status] IN (1, 2, 3, 7, 13, 14, 15))
        OR s.[Status] IN (SELECT Value FROM Reports.ssrs.ParameterSplit(@StoreStatus, ','))
    )
    AND (@OnlyRemitClubs = 0 OR cl.IsRemitClubEnabled = 1)
    AND (
        @Canada IS NULL
        OR (@Canada = 1 AND gp.clubcountry = 'CA')
        OR (@Canada = 2 AND (gp.clubcountry <> 'CA' OR gp.clubcountry IS NULL))
        OR (@Canada = 3 AND (gp.clubcountry IN ('US', 'United States') OR gp.clubcountry IS NULL) 
            AND gp.ClubState NOT IN ('British Columbia', 'BC', 'VIC', 'PR'))
    )
    AND (@ClubState = 'QQ' OR gp.ClubState IN (SELECT Value FROM Reports.ssrs.ParameterSplit(@ClubState, ',')))
    AND (@SiteType IS NULL OR ISNULL(b.SiteTypeId, 0) IN (SELECT Value FROM Reports.ssrs.ParameterSplit(@SiteType, ',')))
    OPTION (OPTIMIZE FOR UNKNOWN);
END;

IF @BrandId IS NOT NULL
BEGIN
    IF @BrandId = '0'
    BEGIN
        ;WITH BrandsCTE AS (
            SELECT BrandId = CAST(
                CASE
                    WHEN c.ChainName LIKE 'BRAND_D%' THEN BRAND_ID_1
                    WHEN c.ChainName LIKE 'BRAND_S%' OR c.ChainName LIKE 'BRAND_R%' THEN BRAND_ID_2
                    WHEN c.ChainName LIKE 'BRAND_F%' THEN BRAND_ID_3
     ------
                    WHEN c.ChainName LIKE 'BRAND_J%' THEN BRAND_ID_14
                    WHEN c.ChainName LIKE 'BRAND_P%' THEN BRAND_ID_15
                    ELSE c.ChainID
                END AS VARCHAR(10))
            FROM ClubReady.dbo.Chains c WITH (NOLOCK)
            WHERE Deleted IS NULL AND ChainName <> '' 
                  AND c.ChainName NOT LIKE '%test%' AND c.ChainName NOT LIKE '%demo%' 
                  AND c.ChainName NOT LIKE '%delete%' AND c.ChainID NOT IN (CHAIN_ID_A, CHAIN_ID_B, CHAIN_ID_C, CHAIN_ID_D, CHAIN_ID_E, CHAIN_ID_F)
            UNION ALL
            SELECT BrandId = 'BRAND_ID_NO_ASSIGN'
            UNION ALL
            SELECT BrandId = 'BRAND_ID_PIQ'
            UNION ALL
            SELECT BrandId = 'BRAND_ID_AURORA'
            UNION ALL
            SELECT BrandId = 'BRAND_ID_IKIZMET'
        )
        SELECT @BrandId = COALESCE(@BrandId + ',', '') + CAST(BrandId AS VARCHAR(10))
        FROM BrandsCTE;
    END;

    INSERT INTO #stores
    SELECT
        ChainId = CASE
            WHEN gp.LocationName LIKE 'BRAND_D%' THEN BRAND_ID_1
            WHEN gp.LocationName LIKE 'BRAND_R%' OR c.ChainName LIKE 'BRAND_S%' THEN BRAND_ID_2
------
            WHEN gp.LocationName LIKE 'BRAND_H%' THEN BRAND_ID_13
            WHEN gp.LocationName LIKE 'BRAND_J%' THEN BRAND_ID_14
            WHEN gp.LocationName LIKE 'BRAND_P%' THEN BRAND_ID_15
            ELSE s.ChainID
        END,
        ChainIdRebates = CASE
            WHEN s.ChainID IS NULL OR s.ChainID = CHAIN_ID_X THEN
                CASE
                    WHEN gp.LocationName LIKE 'BRAND_A%' AND gp.clubcountry = 'US' THEN REBATE_ID_1
                    WHEN gp.LocationName LIKE 'BRAND_B%' AND gp.clubcountry = 'US' THEN REBATE_ID_2
                    WHEN gp.LocationName LIKE 'BRAND_C%' AND gp.clubcountry = 'US' THEN REBATE_ID_3
------
                    WHEN gp.LocationName LIKE 'BRAND_P%' AND gp.clubcountry = 'US' THEN REBATE_ID_21
                    WHEN gp.LocationName LIKE 'BRAND_P%' AND gp.clubcountry = 'CA' THEN REBATE_ID_22
                    WHEN gp.LocationName LIKE 'BRAND_Q%' AND gp.clubcountry = 'CA' THEN REBATE_ID_23
                END
            ELSE s.ChainID
        END,
        ChainName = CASE
            WHEN gp.LocationName LIKE 'BRAND_D%' THEN 'BRAND_D'
            WHEN gp.LocationName LIKE 'BRAND_R%' OR c.ChainName LIKE 'BRAND_S%' THEN 'BRAND_S'
            WHEN gp.LocationName LIKE 'BRAND_F%' THEN 'BRAND_F'
            WHEN gp.LocationName LIKE 'BRAND_G%' THEN 'BRAND_G'
            WHEN gp.LocationName LIKE 'BRAND_T%' THEN 'BRAND_T'
-------
            WHEN gp.LocationName LIKE 'BRAND_P%' THEN 'BRAND_P'
            ELSE ISNULL(c.ChainName, 'No Brand Assigned')
        END,
        BrandName = CASE
            WHEN gp.LocationName LIKE 'BRAND_D%' THEN 'BRAND_D'
            WHEN gp.LocationName LIKE 'BRAND_R%' OR c.ChainName LIKE 'BRAND_S%' THEN 'BRAND_S'
            WHEN gp.LocationName LIKE 'BRAND_F%' THEN 'BRAND_F'
-------
            WHEN gp.LocationName LIKE 'BRAND_P%' THEN 'BRAND_P'
            ELSE ISNULL(c.ChainName, 'No Brand Assigned')
        END,
        s.StoreID,
        LocationName = gp.LocationName + CASE WHEN s.Deleted = 1 THEN ' (Deleted)' ELSE '' END,
        gp.clubcountry,
        gp.ClubState,
        s.[Status],
        StoreStatus = ss.[Name],
        SiteType = ISNULL(st.[Name], 'No Site Type'),
        gp.TimeOffset,
        RemitGroup = ISNULL(co.CompanyName, 'DIY'),
        co.CASCompanyID,
        co.IsRemitGroupEnabled,
        cl.IsRemitClubEnabled,
        s.CollectionsBy,
        AccrualBalance = CAST(NULL AS DECIMAL(17, 2)),
        s.Deleted,
        b.SiteTypeId,
        BillingType = CASE WHEN cl.CasClubId IS NOT NULL THEN 'FS' ELSE 'DIY' END,
        [Address] = TRIM(ISNULL(ClubAddress, '')) + ' ' + TRIM(ISNULL(ClubCity, '')) + 
                    CASE WHEN ISNULL(ClubState, '') = '' THEN ' ' ELSE ', ' END + 
                    TRIM(ISNULL(ClubState, '')) + ' ' + TRIM(ISNULL(ClubZip, '')),
        [State] = TRIM(ISNULL(
            CASE
                WHEN ClubState = 'Kentucky' THEN 'KY'
                WHEN ClubState = 'Massachusetts' THEN 'MA'
                -----
                ELSE ClubState
            END, ''))
    FROM ClubReady.dbo.Stores s WITH (NOLOCK)
    LEFT JOIN ClubReady.dbo.GeneralPrefs gp WITH (NOLOCK) ON s.StoreID = gp.StoreID
    LEFT JOIN ClubReady.enum.StoreStatus ss WITH (NOLOCK) ON s.[Status] = ss.StoreStatusId
    LEFT JOIN ClubReady.dbo.Chains c WITH (NOLOCK) ON s.ChainID = c.ChainID
    LEFT JOIN ClubReady.dbo.CasClubs cl WITH (NOLOCK) ON s.StoreID = cl.StoreID
    LEFT JOIN ClubReady.dbo.CasCompanies co WITH (NOLOCK) ON cl.CasCompanyID = co.CASCompanyID
    LEFT JOIN ClubReady.dbo.StoreInfoBackOffice b WITH (NOLOCK) ON s.StoreID = b.StoreId
    LEFT JOIN ClubReady.dbo.SiteType st WITH (NOLOCK) ON b.SiteTypeId = st.SiteTypeId
    WHERE CASE
        WHEN gp.LocationName LIKE 'BRAND_D%' THEN BRAND_ID_1
        WHEN gp.LocationName LIKE 'BRAND_R%' OR c.ChainName LIKE 'BRAND_S%' THEN BRAND_ID_2
        WHEN gp.LocationName LIKE 'BRAND_F%' THEN BRAND_ID_3
        WHEN gp.LocationName LIKE 'BRAND_G%' THEN BRAND_ID_4
        WHEN gp.LocationName LIKE 'BRAND_T%' THEN BRAND_ID_5
        WHEN gp.LocationName LIKE 'BRAND_U%' THEN BRAND_ID_6
        WHEN gp.LocationName LIKE 'BRAND_V%' THEN BRAND_ID_7
        WHEN gp.LocationName LIKE 'BRAND_W%' THEN BRAND_ID_8
        WHEN gp.LocationName LIKE 'BRAND_Q%' THEN BRAND_ID_9
        WHEN gp.LocationName LIKE 'BRAND_A%' THEN BRAND_ID_10
        WHEN gp.LocationName LIKE 'BRAND_B%' THEN BRAND_ID_11
        WHEN gp.LocationName LIKE 'BRAND_Y%' THEN BRAND_ID_12
        WHEN gp.LocationName LIKE 'BRAND_H%' THEN BRAND_ID_13
        WHEN gp.LocationName LIKE 'BRAND_J%' THEN BRAND_ID_14
        WHEN gp.LocationName LIKE 'BRAND_P%' THEN BRAND_ID_15
        ELSE ISNULL(s.ChainID, BRAND_ID_NO_ASSIGN)
    END IN (SELECT Value FROM Reports.ssrs.ParameterSplit(@BrandId, ','))
    AND (
        @Canada IS NULL
        OR (@Canada = 1 AND gp.clubcountry = 'CA')
        OR (@Canada = 2 AND (gp.clubcountry <> 'CA' OR gp.clubcountry IS NULL))
        OR (@Canada = 3 AND (gp.clubcountry IN ('US', 'United States') OR gp.clubcountry IS NULL) 
            AND gp.ClubState NOT IN ('British Columbia', 'BC', 'VIC', 'PR'))
    )
    AND (@ClubState = 'QQ' OR gp.ClubState IN (SELECT Value FROM Reports.ssrs.ParameterSplit(@ClubState, ',')))
    AND s.[Status] IN (1, 2, 3, 7, 13, 14, 15)
    OPTION (OPTIMIZE FOR UNKNOWN);
END;

DELETE FROM #stores WHERE SiteTypeId = 4;

UPDATE #stores
SET AccrualBalance = ISNULL(oa.AccrualBalance, 0)
FROM #stores s
OUTER APPLY (
    SELECT AccrualBalance = SUM(a.Amount)
    FROM ClubReady.dbo.RemitAdjustments a WITH (NOLOCK)
    LEFT JOIN ClubReady.dbo.CasReconcile r WITH (NOLOCK) ON a.ReconcileId = r.CasReconcileId
    WHERE a.StoreId = s.StoreId
          AND (a.Accrual = 1 OR a.RemitAdjustmentTypeId = 4)
          AND a.ReconcileId IS NOT NULL
          AND r.Cutoff < @NegAccrualCutoff
    GROUP BY a.StoreId
) oa
OPTION (OPTIMIZE FOR UNKNOWN);

IF @HasNegAccrual IN (1, 2)
BEGIN
    DELETE FROM #stores WHERE AccrualBalance <= 0.00;
END;


IF @TransactionColumns <> 'none'
BEGIN
    SELECT
        pm.StoreID,
        PeriodDisplay = CASE
            WHEN @Period = 1 THEN CAST(YEAR(DATEADD(HOUR, s.TimeOffset, pm.PaymentDate)) AS VARCHAR(4)) + ' - Week ' +
                CAST(CASE WHEN MONTH(DATEADD(HOUR, s.TimeOffset, pm.PaymentDate)) = 1 AND 
                          DATEPART(WEEK, DATEADD(DAY, -1, DATEADD(HOUR, s.TimeOffset, pm.PaymentDate))) > 50 THEN 1
                          ELSE DATEPART(WEEK, DATEADD(DAY, -1, DATEADD(HOUR, s.TimeOffset, pm.PaymentDate))) END AS VARCHAR(2))
            WHEN @Period = 2 THEN CAST(YEAR(DATEADD(HOUR, s.TimeOffset, pm.PaymentDate)) AS VARCHAR(4)) + ' - ' + 
                CAST(DATENAME(MONTH, DATEADD(HOUR, s.TimeOffset, pm.PaymentDate)) AS VARCHAR(20))
            WHEN @Period = 3 THEN CAST(YEAR(DATEADD(HOUR, s.TimeOffset, pm.PaymentDate)) AS VARCHAR(4)) + ' - Q' + 
                CAST(DATEPART(QUARTER, DATEADD(HOUR, s.TimeOffset, pm.PaymentDate)) AS VARCHAR(1))
            WHEN @Period = 4 THEN CAST(YEAR(DATEADD(HOUR, s.TimeOffset, pm.PaymentDate)) AS VARCHAR(4))
        END,
        TransactionCategory = CASE
            WHEN pm.PurchaseWith = 1 THEN 'CC Txn'
            WHEN pm.PurchaseWith = 6 THEN 'eCheck Txn'
            ELSE 'Other Txn'
        END,
        TransactionType = 'Transactions',
        Amount = SUM(CAST(NULLIF(NULLIF(REPLACE(REPLACE(REPLACE(ISNULL(pm.TotalAmount, pm.Amount), '$', ''), ',', ''), '..', '.'), ''), ' ') AS DECIMAL(17, 2))),
        TransactionCount = COUNT(pm.PaymentID)
    INTO #transactions
    FROM ClubReady.dbo.Payments pm WITH (NOLOCK)
    INNER JOIN #stores s ON pm.StoreID = s.StoreId
    WHERE pm.StoreID IN (SELECT StoreId FROM #stores)
          AND pm.PaymentDate >= DATEADD(HOUR, -s.TimeOffset, @StartDate)
          AND pm.PaymentDate < DATEADD(HOUR, -s.TimeOffset, @EndDate)
          AND (
              @TransactionColumns LIKE '%all%'
              OR (@TransactionColumns LIKE '%cc%' AND pm.PurchaseWith = 1)
              OR (@TransactionColumns LIKE '%ec%' AND pm.PurchaseWith = 6)
          )
    GROUP BY pm.StoreID,
             CASE
                 WHEN @Period = 1 THEN CAST(YEAR(DATEADD(HOUR, s.TimeOffset, pm.PaymentDate)) AS VARCHAR(4)) + ' - Week ' +
                     CAST(CASE WHEN MONTH(DATEADD(HOUR, s.TimeOffset, pm.PaymentDate)) = 1 AND 
                               DATEPART(WEEK, DATEADD(DAY, -1, DATEADD(HOUR, s.TimeOffset, pm.PaymentDate))) > 50 THEN 1
                               ELSE DATEPART(WEEK, DATEADD(DAY, -1, DATEADD(HOUR, s.TimeOffset, pm.PaymentDate))) END AS VARCHAR(2))
                 WHEN @Period = 2 THEN CAST(YEAR(DATEADD(HOUR, s.TimeOffset, pm.PaymentDate)) AS VARCHAR(4)) + ' - ' + 
                     CAST(DATENAME(MONTH, DATEADD(HOUR, s.TimeOffset, pm.PaymentDate)) AS VARCHAR(20))
                 WHEN @Period = 3 THEN CAST(YEAR(DATEADD(HOUR, s.TimeOffset, pm.PaymentDate)) AS VARCHAR(4)) + ' - Q' + 
                     CAST(DATEPART(QUARTER, DATEADD(HOUR, s.TimeOffset, pm.PaymentDate)) AS VARCHAR(1))
                 WHEN @Period = 4 THEN CAST(YEAR(DATEADD(HOUR, s.TimeOffset, pm.PaymentDate)) AS VARCHAR(4))
             END;
END;


--SSRS FF Report--
USE [Reports]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [ssrs].[FranchiseFees_9Round]
    @ChainId INT,
    @StartDate DATETIME,
    @EndDate DATETIME,
    @StoreId INT = NULL
AS 
/*
DECLARE @ChainId INT = CHAIN_ID_Y,
        @StartDate DATETIME = '1/1/2025',
        @EndDate DATETIME = '1/31/2025',
        @StoreId INT = NULL;
*/

SET NOCOUNT ON;

DECLARE @EndDateMod DATE = DATEADD(DAY, 1, @EndDate),
        @RecGUID UNIQUEIDENTIFIER = NEWID(),
        @monthstart DATE = DATEADD(DAY, 1, EOMONTH(@EndDate)),
        @StoreIdForORec INT,
        @LocNameForORec VARCHAR(255),
        @ClubStateForORec VARCHAR(255),
        @ExternalStoreId VARCHAR(50),
        @CollectionsBy INT;

SELECT TOP 1
       @StoreIdForORec = s.StoreID,
       @LocNameForORec = g.LocationName + ' [' + CAST(s.StoreID AS VARCHAR(15)) + ']',
       @ClubStateForORec = RTRIM(LTRIM(ISNULL(g.ClubState, ''))),
       @ExternalStoreId = s.ExternalStoreID,
       @CollectionsBy = s.CollectionsBy
FROM ClubReady.dbo.Stores s WITH (NOLOCK)
JOIN ClubReady.dbo.GeneralPrefs g WITH (NOLOCK) ON s.StoreID = g.StoreID
WHERE s.ChainID = @ChainId
      AND (@StoreId IS NULL OR s.StoreID = @StoreId)
OPTION (OPTIMIZE FOR UNKNOWN);

IF OBJECT_ID('tempdb..#stagingtable') IS NOT NULL
    DROP TABLE #stagingtable;

CREATE TABLE #stagingtable
(
    [ReportGUID] [UNIQUEIDENTIFIER] NULL,
    [CoreId] [INT] NULL,
    [CoreTypeId] [SMALLINT] NULL,
    [Location] [VARCHAR](250) NULL,
    [ClubState] [VARCHAR](50) NULL,
    [Category] [VARCHAR](100) NULL,
    [Amount] [DECIMAL](17, 2) NULL,
    [ExternalStoreId] [VARCHAR](50) NULL,
    [CollectionsBy] INT NULL
);
CREATE NONCLUSTERED INDEX IX_ReportGUID ON #stagingtable (ReportGUID);

INSERT INTO #stagingtable
(
    ReportGUID, CoreId, CoreTypeId, Location, ClubState, Category, Amount, ExternalStoreId, CollectionsBy
)
SELECT @RecGUID, @StoreIdForORec, 3, @LocNameForORec, @ClubStateForORec, Category, 0, @ExternalStoreId, @CollectionsBy
FROM (
    VALUES
        ('franchisefee1'), ('franchisefee1Adj'), ('franchisefee2'), ('franchisefee2Adj'),
        ('CardPresent'), ('Down'), ('Products'), ('Draft'), ('Collections'), ('Refunds'),
        ('Returns'), ('NetTotal'), ('Tax'), ('TotalAfterTax'), ('CrCardDraft'),
        ('ECheckDraft'), ('CashDraft'), ('WrittenCheckDraft'), ('ExtTerminalDraft'),
        ('ACHAdjustments'), ('AmexAdjustments'), ('HeartMonitorFee'), ('CorporateEmailFee'),
        ('InsuranceFee'), ('CorporateFee'), ('CorpAdj'), ('DigitalMarketingService'),
        ('SoftwareFee'), ('directcoll'), ('RemitStatementFee'), ('LeadSpeakFee'),
        ('NowFee'), ('EmmaFee'), ('WorkoutScreens'), ('PCICompliance'), ('CRConnect'),
        ('VTS')
) AS X (Category)
UNION ALL
SELECT @RecGUID, CoreId, CoreTypeId, Location, ClubState, Category, Amount, ExternalStoreId, CollectionsBy
FROM (
    SELECT DISTINCT
           CoreId = l.CoreId,
           CoreTypeId = l.CoreTypeId,
           [Location] = g.LocationName + ' [' + CAST(l.CoreId AS VARCHAR(15)) + ']',
           ClubState = RTRIM(LTRIM(ISNULL(g.ClubState, ''))),
           l.ReconcileId, l.ToDate, l.FromDate,
           Down = CAST(l.UpFront_PilTotal_Total AS DECIMAL(17, 2)),
           Draft = CAST(l.Draft_PilTotal_Total AS DECIMAL(17, 2)),
           Products = CAST(l.Product_PilTotal_Total AS DECIMAL(17, 2)),
           Collections = CAST(l.Pdc_PilTotal_Total AS DECIMAL(17, 2)),
           DirectColl = CAST(l.PdcDirect_PilTotal_Total AS DECIMAL(17, 2)),
           Refunds = CAST(l.Refund_RefundTotal_Total AS DECIMAL(17, 2)),
           [Returns] = CAST(l.Return_PaymentTotal_Total AS DECIMAL(17, 2)),
           NetTotal = CAST(l.Net_Total AS DECIMAL(17, 2)),
           Tax = CAST(l.SalesTax_Total AS DECIMAL(17, 2)),
           TotalAfterTax = CAST(l.Total_AfterTax AS DECIMAL(17, 2)),
           CardPresent = CAST(crdprs.CardPresent AS DECIMAL(17, 2)),
           CrCardDraft = CAST(l.Draft_PilTotal_Vmd + l.Draft_PilTotal_Amex AS DECIMAL(17, 2)),
           ECheckDraft = CAST(l.Draft_PilTotal_Ach AS DECIMAL(17, 2)),
           CashDraft = CAST(l.Draft_PilTotal_Cash AS DECIMAL(17, 2)),
           WrittenCheckDraft = CAST(l.Draft_PilTotal_WrittenCheck AS DECIMAL(17, 2)),
           ExtTerminalDraft = CAST(l.Draft_PilTotal_External AS DECIMAL(17, 2)),
           ACHAdjustments = CAST(ISNULL(ach.ACHAdjustments, 0) AS DECIMAL(17, 2)),
           AmexAdjustments = CAST(ISNULL(amex.AmexAdjustments, 0) AS DECIMAL(17, 2)),
           CorpAdj = CAST(ra.CorpAdj AS DECIMAL(17, 2)),
           CollectionsBy,
           HeartMonitorFee = CAST(hr.HeartMonitorFee AS DECIMAL(17, 2)),
           CorporateEmailFee = CAST(email.CorpEmailFee AS DECIMAL(17, 2)),
           DigitalMarketingService = CAST(dms.DigitalMarketingService AS DECIMAL(17, 2)),
           NowFee = CAST(now.NowFee AS DECIMAL(17, 2)),
           EmmaFee = CAST(emma.EmmaFee AS DECIMAL(17, 2)),
           WorkoutScreens = CAST(ws.WorkoutScreens AS DECIMAL(17, 2)),
           PCICompliance = CAST(pci.PCICompliance AS DECIMAL(17, 2)),
           CRConnect = CAST(crc.CRConnect AS DECIMAL(17, 2)),
           VTS = CAST(vts.VTS AS DECIMAL(17, 2)),
           ExternalStoreID
    FROM ClubReady.Finance.SettlementLogV3 l WITH (NOLOCK)
    JOIN ClubReady.dbo.Stores s ON l.CoreId = s.StoreID AND l.CoreTypeId = 3
    LEFT JOIN ClubReady.dbo.GeneralPrefs g ON s.StoreID = g.StoreID
    OUTER APPLY (
        SELECT CardPresent = SUM(ClubReady.util.ToDecimal172(TotalAmount))
        FROM ClubReady.dbo.Payments
        WHERE StoreID = s.StoreID AND CAST(PaymentDate AS DATE) BETWEEN l.FromDate AND l.ToDate
              AND PurchaseWith = 1 AND GatewayType = 'CP'
    ) crdprs
    OUTER APPLY (
        SELECT ACHAdjustments = SUM(ra.Amount)
        FROM ClubReady.dbo.RemitAdjustments ra WITH (NOLOCK)
        WHERE ra.CreatedByReconcileId = l.ReconcileId AND ra.QuickbookSubcategoryId IN (85, 86)
              AND ra.StoreId = l.CoreId
    ) ach
    OUTER APPLY (
        SELECT AmexAdjustments = SUM(-ra.Amount)
        FROM ClubReady.dbo.RemitAdjustments ra WITH (NOLOCK)
        WHERE ra.CreatedByReconcileId = l.ReconcileId AND ra.QuickbookSubcategoryId IN (80, 81)
              AND ra.StoreId = l.CoreId
    ) amex
    OUTER APPLY (
        SELECT CorpAdj = SUM(ra.Amount)
        FROM ClubReady.dbo.RemitAdjustments ra
        LEFT JOIN ClubReady.dbo.CasClubs cc ON ra.StoreId = cc.StoreID
        WHERE l.ReconcileId = ra.ReconcileId AND l.CoreTypeId = ra.CoreTypeId AND l.CoreId = ra.CoreId
              AND ra.Chain = 1 AND ra.AdjustmentForFeeId IS NULL
    ) ra
    OUTER APPLY (
        SELECT HeartMonitorFee = SUM(slf.Amount)
        FROM ClubReady.Finance.SettlementLogFee slf
        JOIN ClubReady.Finance.SettlementLogV3 sl ON slf.SettlementLogId = sl.SettlementLogId
        JOIN ClubReady.Finance.SettlementLogV3 rs ON sl.ReconcileId = rs.ReconcileId 
             AND sl.CoreId = rs.CoreId AND sl.CoreTypeId = rs.CoreTypeId
        WHERE slf.FeeCategoryId = 3 AND FeeName LIKE 'Heart%' AND s.StoreID = rs.CoreId
              AND sl.FromDate BETWEEN l.FromDate AND l.ToDate
    ) hr
    OUTER APPLY (
        SELECT CorpEmailFee = SUM(slf.Amount)
        FROM ClubReady.Finance.SettlementLogFee slf
        JOIN ClubReady.Finance.SettlementLogV3 sl ON slf.SettlementLogId = sl.SettlementLogId
        JOIN ClubReady.Finance.SettlementLogV3 rs ON sl.ReconcileId = rs.ReconcileId 
             AND sl.CoreId = rs.CoreId AND sl.CoreTypeId = rs.CoreTypeId
        WHERE FeeCategoryId = 3 AND FeeName LIKE '%Corp%Email%' AND s.StoreID = rs.CoreId
              AND sl.FromDate BETWEEN l.FromDate AND l.ToDate
    ) email
    OUTER APPLY (
        SELECT DigitalMarketingService = SUM(slf.Amount)
        FROM ClubReady.Finance.SettlementLogFee slf
        JOIN ClubReady.Finance.SettlementLogV3 sl ON slf.SettlementLogId = sl.SettlementLogId
        JOIN ClubReady.Finance.SettlementLogV3 rs ON sl.ReconcileId = rs.ReconcileId 
             AND sl.CoreId = rs.CoreId AND sl.CoreTypeId = rs.CoreTypeId
        WHERE FeeCategoryId = 3 AND (FeeName LIKE '%Digital Marketing Service%') AND s.StoreID = rs.CoreId
              AND sl.FromDate BETWEEN l.FromDate AND l.ToDate
    ) dms
    OUTER APPLY (
        SELECT NowFee = SUM(slf.Amount)
        FROM ClubReady.Finance.SettlementLogFee slf
        JOIN ClubReady.Finance.SettlementLogV3 sl ON slf.SettlementLogId = sl.SettlementLogId
        JOIN ClubReady.Finance.SettlementLogV3 rs ON sl.ReconcileId = rs.ReconcileId 
             AND sl.CoreId = rs.CoreId AND sl.CoreTypeId = rs.CoreTypeId
        WHERE FeeCategoryId = 3 AND (FeeName LIKE '%9r%now%') AND s.StoreID = rs.CoreId
              AND sl.FromDate BETWEEN l.FromDate AND l.ToDate
    ) now
    OUTER APPLY (
        SELECT EmmaFee = SUM(slf.Amount)
        FROM ClubReady.Finance.SettlementLogFee slf
        JOIN ClubReady.Finance.SettlementLogV3 sl ON slf.SettlementLogId = sl.SettlementLogId
        JOIN ClubReady.Finance.SettlementLogV3 rs ON sl.ReconcileId = rs.ReconcileId 
             AND sl.CoreId = rs.CoreId AND sl.CoreTypeId = rs.CoreTypeId
        WHERE FeeCategoryId = 3 AND (FeeName LIKE 'emma%') AND s.StoreID = rs.CoreId
              AND sl.FromDate BETWEEN l.FromDate AND l.ToDate
    ) emma
    OUTER APPLY (
        SELECT WorkoutScreens = SUM(slf.Amount)
        FROM ClubReady.Finance.SettlementLogFee slf
        JOIN ClubReady.Finance.SettlementLogV3 sl ON slf.SettlementLogId = sl.SettlementLogId
        JOIN ClubReady.Finance.SettlementLogV3 rs ON sl.ReconcileId = rs.ReconcileId 
             AND sl.CoreId = rs.CoreId AND sl.CoreTypeId = rs.CoreTypeId
        WHERE FeeCategoryId = 3 AND (FeeName LIKE 'Workout Screens%') AND s.StoreID = rs.CoreId
              AND sl.FromDate BETWEEN l.FromDate AND l.ToDate
    ) ws
    OUTER APPLY (
        SELECT PCICompliance = SUM(slf.Amount)
        FROM ClubReady.Finance.SettlementLogFee slf
        JOIN ClubReady.Finance.SettlementLogV3 sl ON slf.SettlementLogId = sl.SettlementLogId
        JOIN ClubReady.Finance.SettlementLogV3 rs ON sl.ReconcileId = rs.ReconcileId 
             AND sl.CoreId = rs.CoreId AND sl.CoreTypeId = rs.CoreTypeId
        WHERE FeeCategoryId = 17 AND (FeeName LIKE '%PCI Compliance%') AND s.StoreID = rs.CoreId
              AND sl.FromDate BETWEEN l.FromDate AND l.ToDate
    ) pci
    OUTER APPLY (
        SELECT CRConnect = SUM(slf.Amount)
        FROM ClubReady.Finance.SettlementLogFee slf
        JOIN ClubReady.Finance.SettlementLogV3 sl ON slf.SettlementLogId = sl.SettlementLogId
        JOIN ClubReady.Finance.SettlementLogV3 rs ON sl.ReconcileId = rs.ReconcileId 
             AND sl.CoreId = rs.CoreId AND sl.CoreTypeId = rs.CoreTypeId
        WHERE slf.FeeCategoryId = 35 AND (slf.FeeName LIKE '%CR%Connect%') AND s.StoreID = rs.CoreId
              AND sl.FromDate BETWEEN l.FromDate AND l.ToDate
    ) crc
    OUTER APPLY (
        SELECT VTS = SUM(slf.Amount)
        FROM ClubReady.Finance.SettlementLogFee slf
        JOIN ClubReady.Finance.SettlementLogV3 sl ON slf.SettlementLogId = sl.SettlementLogId
        JOIN ClubReady.Finance.SettlementLogV3 rs ON sl.ReconcileId = rs.ReconcileId 
             AND sl.CoreId = rs.CoreId AND sl.CoreTypeId = rs.CoreTypeId
        WHERE FeeCategoryId = 3 AND (FeeName LIKE '%VTS%') AND s.StoreID = rs.CoreId
              AND sl.FromDate BETWEEN l.FromDate AND l.ToDate
    ) vts
    WHERE s.ChainID = @ChainId AND (@StoreId IS NULL OR CoreId = @StoreId)
          AND l.ToDate >= @StartDate AND l.ToDate < @EndDateMod
) p
UNPIVOT (
    Amount FOR Category IN (
        [Down], [Draft], [Products], Collections, DirectColl, [Refunds], [Returns], Tax,
        [TotalAfterTax], [NetTotal], CrCardDraft, ECheckDraft, CashDraft, WrittenCheckDraft,
        ExtTerminalDraft, ACHAdjustments, AmexAdjustments, CorpAdj, CorporateEmailFee,
        HeartMonitorFee, DigitalMarketingService, NowFee, EmmaFee, WorkoutScreens, PCICompliance,
        CardPresent, CRConnect, VTS
    )
) AS unpvt
UNION ALL
SELECT @RecGUID, l.CoreId, l.CoreTypeId, 
       Location = g.LocationName + ' [' + CAST(l.CoreId AS VARCHAR(15)) + ']',
       ClubState = RTRIM(LTRIM(ISNULL(g.ClubState, ''))),
       Category = c.[Name], f.Amount, ExternalStoreID, CollectionsBy
FROM ClubReady.Finance.SettlementLogV3 l
JOIN ClubReady.Finance.SettlementLogFee f ON l.SettlementLogId = f.SettlementLogId
JOIN ClubReady.Finance.ReconcileFee r ON f.ReconcileFeeId = r.ReconcileFeeId
LEFT JOIN ClubReady.enum.FeeCategory c ON f.FeeCategoryId = c.FeeCategoryId
JOIN ClubReady.dbo.Stores s ON (l.CoreId = s.StoreID AND l.CoreTypeId = 3)
LEFT JOIN ClubReady.dbo.GeneralPrefs g ON s.StoreID = g.StoreID
WHERE s.ChainID = @ChainId AND l.ToDate >= @StartDate AND l.ToDate < @EndDateMod
      AND (@StoreId IS NULL OR s.StoreID = @StoreId) AND f.FeeCategoryId <> 3
UNION ALL
SELECT DISTINCT @RecGUID, l.CoreId, l.CoreTypeId,
       Location = g.LocationName + ' [' + CAST(l.CoreId AS VARCHAR(15)) + ']',
       ClubState = RTRIM(LTRIM(ISNULL(g.ClubState, ''))),
       Category = LTRIM(RTRIM(c.Name)) + 'adj',
       Amount = SUM(ISNULL(a.Amount, 0)) OVER (PARTITION BY c.Name, l.CoreId, l.CoreTypeId, g.LocationName),
       ExternalStoreID, CollectionsBy
FROM ClubReady.Finance.SettlementLogV3 l
JOIN ClubReady.dbo.RemitAdjustments a ON l.ReconcileId = a.ReconcileId AND l.CoreId = a.CoreId AND l.CoreTypeId = a.CoreTypeId
JOIN ClubReady.Finance.ReconcileFee r ON a.AdjustmentForFeeId = r.ReconcileFeeId
LEFT JOIN ClubReady.enum.FeeCategory c ON r.FeeCategoryId = c.FeeCategoryId
JOIN ClubReady.dbo.Stores s ON l.CoreId = s.StoreID AND l.CoreTypeId = 3
LEFT JOIN ClubReady.dbo.GeneralPrefs g ON s.StoreID = g.StoreID
LEFT JOIN ClubReady.dbo.Chains ch ON ch.ChainID = s.ChainID
WHERE s.ChainID = @ChainId AND l.ToDate >= @StartDate AND l.ToDate < @EndDateMod
      AND (@StoreId IS NULL OR l.CoreId = @StoreId)
OPTION (OPTIMIZE FOR UNKNOWN);

DECLARE @cols AS NVARCHAR(MAX),
        @Params AS NVARCHAR(MAX),
        @query AS NVARCHAR(MAX);

SELECT @cols = STUFF((
    SELECT ',' + QUOTENAME(Category)
    FROM #stagingtable
    WHERE ReportGUID = @RecGUID
    GROUP BY Category
    ORDER BY Category
    FOR XML PATH(''), TYPE
).value('.', 'NVARCHAR(MAX)'), 1, 1, '');

SELECT @query = N'
IF OBJECT_ID(''tempdb..#temptable'') IS NOT NULL DROP TABLE #temptable;

WITH CTE AS (
    SELECT Location, StoreId = CoreId, ExternalStoreID, CollectionsBy, ChainName, ChainId, ClubState, ' + @cols + N'
    FROM (
        SELECT a.CoreId, a.CoreTypeId, a.Location, ExternalStoreID, a.CollectionsBy, ChainName, ChainId, a.ClubState,
               Category = a.Category, Amount = ISNULL(Amount, 0)
        FROM #stagingtable a
        JOIN ClubReady.Reports.StoreDetail sd ON sd.StoreId = a.CoreId
        LEFT JOIN ClubReady.dbo.CasClubs cc WITH (NOLOCK) ON cc.StoreId = a.CoreId
        WHERE ReportGUID = @InRecGUID
    ) x
    PIVOT (SUM(Amount) FOR Category IN (' + @cols + N')) p
)
SELECT *, CurrentAccrualBalance = CAST(NULL AS DECIMAL(17,2)), PastAccrualBalance = CAST(NULL AS DECIMAL(17,2))
INTO #temptable FROM CTE;

UPDATE #temptable SET SoftwareFee = 0 WHERE SoftwareFee IS NULL;
UPDATE #temptable SET RemitStatementFee = 0 WHERE RemitStatementFee IS NULL;
UPDATE #temptable SET NowFee = 0 WHERE NowFee IS NULL;
UPDATE #temptable SET EmmaFee = 0 WHERE EmmaFee IS NULL;

UPDATE #temptable
SET PastAccrualBalance = ISNULL(oa.AccrualBalance, 0)
FROM #temptable t
OUTER APPLY (
    SELECT AccrualBalance = -SUM(a.Amount)
    FROM ClubReady.dbo.RemitAdjustments a WITH (NOLOCK)
    LEFT JOIN ClubReady.dbo.CASReconcile r WITH (NOLOCK) ON a.ReconcileId = r.CASReconcileId
    WHERE a.StoreId = t.StoreId AND (a.Accrual = 1 OR a.RemitAdjustmentTypeId = 4)
          AND a.ReconcileId IS NOT NULL AND r.CutOff < @ReportDate
    GROUP BY a.StoreId
) oa;

UPDATE #temptable
SET CurrentAccrualBalance = ISNULL(oa.AccrualBalance, 0)
FROM #temptable t
OUTER APPLY (
    SELECT AccrualBalance = -SUM(a.Amount)
    FROM ClubReady.dbo.RemitAdjustments a WITH (NOLOCK)
    LEFT JOIN ClubReady.dbo.CASReconcile r WITH (NOLOCK) ON a.ReconcileId = r.CASReconcileId
    WHERE a.StoreId = t.StoreId AND (a.Accrual = 1 OR a.RemitAdjustmentTypeId = 4)
          AND a.ReconcileId IS NOT NULL AND r.CutOff < DATEADD(MONTH, -1, @ReportDate)
    GROUP BY a.StoreId
) oa;

SELECT tt.*, WorkoutSystemFee = ISNULL(wsf.WorkoutSystemFee, 0), TechnologyFee = ISNULL(tf.TechnologyFee, 0), 
       PersonalTrainingFee = ISNULL(ptf.PersonalTrainingFee, 0)
FROM #temptable AS tt
OUTER APPLY (
    SELECT WorkoutSystemFee = SUM(rf.FeeMin)
    FROM ClubReady.Finance.ReconcileFee AS rf
    WHERE rf.FeeName LIKE ''%Workout%System%'' AND rf.StartUtc <= GETUTCDATE()
          AND StoreId = CoreId AND CoreTypeId = 3
) AS wsf
OUTER APPLY (
    SELECT TechnologyFee = SUM(rf.FeeMin)
    FROM