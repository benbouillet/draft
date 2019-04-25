--#####################################################################
--######## Getting sales organizations with bu_idr ####################
--#####################################################################
DROP TABLE IF EXISTS salesorg_store_idr;
CREATE TEMP TABLE IF NOT EXISTS salesorg_store_idr
(
	store					VARCHAR(5)	NOT NULL PRIMARY KEY,
	but_idr_business_unit	INT4		NOT NULL,
	cnt_idr_country			INT8		NOT NULL,
	salesorg 				VARCHAR(4)	NOT NULL
)
DISTSTYLE ALL
SORTKEY(store, salesorg);

TRUNCATE salesorg_store_idr;

INSERT INTO salesorg_store_idr
SELECT LTRIM(sa.plant_id,'0') AS store,
       bu.but_idr_business_unit AS but_idr_business_unit,
       bu.cnt_idr_country AS cnt_idr_country,
       sa.sales_org AS salesorg
FROM cds.d_business_unit AS bu
INNER JOIN cds_supply.sites_attribut_0plant_branches AS sa
  		ON LTRIM(sa.plant_id,'0') = CAST(bu.but_num_business_unit AS VARCHAR (5))
WHERE bu.but_num_typ_but = 7
AND   sa.sapsrc = 'PRT';

--#####################################################################
--################# Temp table first sales date #######################
--#####################################################################
DROP TABLE IF EXISTS first_sale_temp;
CREATE TEMP TABLE IF NOT EXISTS first_sale_temp
(
	cnt_idr_country	INT8,
	sku_idr_sku		INT8,
	first_sale		DATE
)
DISTKEY(sku_idr_sku)
SORTKEY(cnt_idr_country, sku_idr_sku);

TRUNCATE first_sale_temp;

INSERT INTO first_sale_temp
SELECT td.cnt_idr_country AS cnt_idr_country,
       td.sku_idr_sku AS sku_idr_sku,
       CAST(DATE_TRUNC ('day',MIN(td.tdt_date_to_ordered)) AS DATE) AS first_sale
FROM cds.f_transaction_detail td
INNER JOIN salesorg_store_idr ssi
        ON ssi.but_idr_business_unit = td.but_idr_business_unit
WHERE	td.the_to_type IN ('offline')
AND   td.tdt_type_detail = 'sale'
AND   td.f_qty_item > 0
GROUP BY td.cnt_idr_country,
         td.sku_idr_sku;

--#####################################################################
--################ Final table first sales date #######################
--#####################################################################
DROP TABLE IF EXISTS first_sale;
CREATE TEMP TABLE IF NOT EXISTS first_sale
(
	cnt_idr_country	INT8,
	sku_idr_sku		INT8,
	first_sale		DATE,
	period_case		INT4
)
DISTKEY(sku_idr_sku)
SORTKEY(cnt_idr_country, sku_idr_sku);

TRUNCATE first_sale;

INSERT INTO first_sale
SELECT fst.cnt_idr_country AS cnt_idr_country,
       fst.sku_idr_sku AS sku_idr_sku,
       first_sale,
       CASE WHEN first_sale > date_trunc('day',CURRENT_TIMESTAMP)-interval '52 week' THEN 1
            WHEN first_sale > date_trunc('day',CURRENT_TIMESTAMP)-interval '104 week' THEN 2
            ELSE 3
       END AS period_case
FROM first_sale_temp fst
INNER JOIN cds.d_sku ds
ON ds.sku_idr_sku = fst.sku_idr_sku
WHERE ds.sku_date_end = '2999-12-31 23:59:59'
	AND	ds.unv_num_univers <> 0;


--#####################################################################
--######################## Weekly sales ###############################
--#####################################################################
DROP TABLE IF EXISTS weekly_sales;
CREATE TEMP TABLE IF NOT EXISTS weekly_sales
(
	cnt_idr_country			INT8,
	but_idr_business_unit	INT4,
	sku_idr_sku				INT8,
	wk_date					DATE,
	qty						INT8
)
DISTKEY(sku_idr_sku)
SORTKEY(cnt_idr_country, sku_idr_sku);

TRUNCATE weekly_sales;

INSERT INTO weekly_sales
SELECT td.cnt_idr_country AS cnt_idr_country,
	   td.but_idr_business_unit,
       td.sku_idr_sku,
       --CAST(the_date_transaction AS DATE) AS date,
       --CAST(the_date_transaction AS DATE)+1  AS date_mod,
       DATEADD(DAY,-1,date_trunc ('week',DATEADD (day,1,td.the_date_transaction))) AS wk_date,
       SUM(td.f_qty_item)
FROM cds.f_transaction_detail td
INNER JOIN salesorg_store_idr ssi
        ON ssi.but_idr_business_unit = td.but_idr_business_unit
WHERE td.the_date_transaction >= date_trunc('week',CURRENT_TIMESTAMP-interval '104 week') -1
AND   td.the_date_transaction < date_trunc('week',CURRENT_TIMESTAMP)
AND   td.the_to_type = 'offline'
AND   td.tdt_type_detail = 'sale'
AND	  td.f_qty_item > 0
--AND   td.sku_idr_sku = 1076359
--AND   td.cnt_idr_country = 94
GROUP BY td.cnt_idr_country,
		 td.but_idr_business_unit,
         td.sku_idr_sku,
         --CAST(the_date_transaction AS DATE),
         --CAST(the_date_transaction AS DATE)+1,
         DATEADD(DAY,-1,date_trunc ('week',DATEADD (day,1,td.the_date_transaction)));

--
SELECT TOP 10000
DISTINCT sk.sku_num_sku_r3
FROM first_sale fs
INNER JOIN cds.d_sku sk
		ON sk.sku_idr_sku = fs.sku_idr_sku
WHERE period_case = 1

--#####################################################################
--######################## Ref Item temp ##############################
--#####################################################################
DROP TABLE IF EXISTS refitem_temp;
CREATE TEMP TABLE IF NOT EXISTS refitem_temp
(
	salesorg					VARCHAR(4),
	sku_idr_sku					INT8,
	ref_but_idr_business_unit	INT4,
	ref_sku_idr_sku				INT8
)

TRUNCATE refitem_temp;

INSERT INTO refitem_temp
SELECT 
ssi.salesorg			 AS salesorg,
sk1.sku_idr_sku 		 AS sku_idr_sku,
bu.but_idr_business_unit AS ref_but_idr_business_unit,
sk2.sku_idr_sku 		 AS ref_sku_idr_sku
FROM cds_supply.f_article_store_ref_datas asr
INNER JOIN cds.d_business_unit bu
		ON CAST(bu.but_num_business_unit AS BPCHAR) = LTRIM(asr.ref_plant_id,'0')
INNER JOIN salesorg_store_idr ssi
		ON ssi.store = LTRIM(asr.plant_id,'0')
INNER JOIN cds.d_sku sk1
		ON CAST(sk1.sku_num_sku_r3 AS BPCHAR) = LTRIM(asr.material_id,'0')
INNER JOIN cds.d_sku sk2
	ON CAST(sk2.sku_num_sku_r3 AS BPCHAR) = LTRIM(asr.ref_material_id,'0')
AND bu.but_num_typ_but = 7
GROUP BY
ssi.salesorg,
sk1.sku_idr_sku,
bu.but_idr_business_unit,
sk2.sku_idr_sku

--#####################################################################
--################### Ref Item temp with qty ##########################
--#####################################################################
DROP TABLE IF EXISTS refitem_temp_qty;
CREATE TEMP TABLE IF NOT EXISTS refitem_temp_qty
(
	salesorg					VARCHAR(4),
	sku_idr_sku					INT8,
	ref_but_idr_business_unit	INT4,
	ref_sku_idr_sku				INT8,
	qty							INT8
)

TRUNCATE refitem_temp_qty;

INSERT INTO refitem_temp_qty
SELECT
rit.salesorg,
rit.sku_idr_sku,
rit.ref_but_idr_business_unit,
rit.ref_sku_idr_sku,
SUM(ws.qty) AS qty
FROM refitem_temp rit
INNER JOIN weekly_sales ws
		ON ws.but_idr_business_unit = rit.ref_but_idr_business_unit
	   AND ws.sku_idr_sku = rit.ref_sku_idr_sku
WHERE rit.salesorg IN ('Z015')
GROUP BY
rit.salesorg,
rit.sku_idr_sku,
rit.ref_but_idr_business_unit,
rit.ref_sku_idr_sku

--#####################################################################
--############### Ref Item temp with max qties ########################
--#####################################################################
DROP TABLE IF EXISTS refitem_temp_qty_max;
CREATE TEMP TABLE IF NOT EXISTS refitem_temp_qty_max
(
	salesorg					VARCHAR(4),
	sku_idr_sku					INT8,
	ref_but_idr_business_unit	INT4,
	ref_sku_idr_sku				INT8,
	qty							INT8
)

TRUNCATE refitem_temp_qty_max;

INSERT INTO refitem_temp_qty_max
SELECT
	ritq1.salesorg AS salesorg,
	ritq1.sku_idr_sku AS sku_idr_sku,
	ritq1.ref_but_idr_business_unit AS ref_but_idr_business_unit,
	ritq1.ref_sku_idr_sku AS ref_sku_idr_sku,
	ritq1.qty AS qty
FROM refitem_temp_qty ritq1
WHERE qty = 
	(SELECT MAX(ritq2.qty)
	 FROM refitem_temp_qty ritq2
 	 WHERE ritq1.sku_idr_sku = ritq2.sku_idr_sku)
 ORDER BY
 ritq1.sku_idr_sku
 

--#####################################################################
--############### Ref Item finale table ###### ########################
--#####################################################################
DROP TABLE IF EXISTS refitem;
CREATE TEMP TABLE IF NOT EXISTS refitem
(
	salesorg					VARCHAR(4),
	sku_idr_sku					INT8,
	ref_but_idr_business_unit	INT4,
	ref_sku_idr_sku				INT8,
	qty							INT8
)

TRUNCATE refitem;

INSERT INTO refitem
SELECT
	ritqm1.salesorg AS salesorg,
	ritqm1.sku_idr_sku AS sku_idr_sku,
	ritqm1.ref_but_idr_business_unit AS ref_but_idr_business_unit,
	ritqm1.ref_sku_idr_sku AS ref_sku_idr_sku,
	ritqm1.qty AS qty
FROM refitem_temp_qty_max ritqm1
WHERE ritqm1.ref_but_idr_business_unit = 
	(SELECT MAX(ritqm2.ref_but_idr_business_unit)
	 FROM refitem_temp_qty_max ritqm2
 	 WHERE ritqm1.sku_idr_sku = ritqm2.sku_idr_sku)

SELECT * FROM refitem
 
SELECT TOP 10 *
FROM refitem_temp_qty
WHERE ref_sku_idr_sku = 2193908
