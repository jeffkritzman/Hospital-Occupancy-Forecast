-------------------------------------------------------------------------------------------------
--
-- Modeling hospital occupancy
--
-- Uses historical data to predict arrivals and how long patients stay,
--  for both current admits and predicted arrivals
--
-- Generally, the term "Predicted" means an arrival stream is forecast using a lookback method,
--   and the term "Expected" means an arrival stream is forecast based on an actual data point
--   (e.g. actual surgical schedule or expected delivery dates)
--
-- Modeling architecture and methodology designed and implemented by Jeff Kritzman
-- Tyler Lantz and Joe Kardos provided some of the specific subject area code snippets to incorporate
--
-------------------------------------------------------------------------------------------------

DECLARE @historicalStartDate DATE = '2018-01-01' --use >= --chose this, as SFCH opened gradually throughout 2017, and this gave a clean year
DECLARE @endDate DATETIME = convert(date, GETDATE(), 101) --use <
DECLARE @daysToPredictForward INT = 30 --use <=
DECLARE @daysToPredictForwardOB INT = 119 --use <= --4 months, as per discussion w/ Dale Geerdes, Teresa Horak, and Bridget Toomey on 4/12/21. Make it 17 weeks for clean numbers.
DECLARE @predictLookbackWindow INT = 28 --use <=

--03 17 2020----------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#ACodeList') IS NOT NULL DROP TABLE #ACodeList
IF OBJECT_ID('tempdb..#dateTable') IS NOT NULL DROP TABLE #dateTable
IF OBJECT_ID('tempdb..#dateTablePre1') IS NOT NULL DROP TABLE #dateTablePre1
IF OBJECT_ID('tempdb..#dateTablePre2') IS NOT NULL DROP TABLE #dateTablePre2
IF OBJECT_ID('tempdb..#allEncounters') IS NOT NULL DROP TABLE #allEncounters
IF OBJECT_ID('tempdb..#scaffold') IS NOT NULL DROP TABLE #scaffold
IF OBJECT_ID('tempdb..#currentAdmitsLOSprobDist') IS NOT NULL DROP TABLE #currentAdmitsLOSprobDist
IF OBJECT_ID('tempdb..#currentAdmitPop') IS NOT NULL DROP TABLE #currentAdmitPop
IF OBJECT_ID('tempdb..#currentAdmitPop2') IS NOT NULL DROP TABLE #currentAdmitPop2
IF OBJECT_ID('tempdb..#currentAdmitFinalScaffold') IS NOT NULL DROP TABLE #currentAdmitFinalScaffold
--03 18 2020----------------------------------------------------------------------------------
--ED Admits--
IF OBJECT_ID('tempdb..#EDpop') IS NOT NULL DROP TABLE #EDpop
IF OBJECT_ID('tempdb..#edLOSprobDist') IS NOT NULL DROP TABLE #edLOSprobDist
IF OBJECT_ID('tempdb..#edPredArrDOW') IS NOT NULL DROP TABLE #edPredArrDOW
IF OBJECT_ID('tempdb..#edPredArr') IS NOT NULL DROP TABLE #edPredArr
IF OBJECT_ID('tempdb..#edFinalScaffold') IS NOT NULL DROP TABLE #edFinalScaffold
--External Transfers--
IF OBJECT_ID('tempdb..#request') IS NOT NULL DROP TABLE #request
IF OBJECT_ID('tempdb..#destination') IS NOT NULL DROP TABLE #destination
IF OBJECT_ID('tempdb..#extTransferPop') IS NOT NULL DROP TABLE #extTransferPop
IF OBJECT_ID('tempdb..#directAdmitLOSprobDist') IS NOT NULL DROP TABLE #directAdmitLOSprobDist
IF OBJECT_ID('tempdb..#directAdmitPredArr') IS NOT NULL DROP TABLE #directAdmitPredArr
IF OBJECT_ID('tempdb..#directAdmitPredArrDOW') IS NOT NULL DROP TABLE #directAdmitPredArrDOW
IF OBJECT_ID('tempdb..#directAdmitFinalScaffold') IS NOT NULL DROP TABLE #directAdmitFinalScaffold
--03 19 2020----------------------------------------------------------------------------------
--"Other"--
IF OBJECT_ID('tempdb..#otherPop') IS NOT NULL DROP TABLE #otherPop
IF OBJECT_ID('tempdb..#otherLOSprobDist') IS NOT NULL DROP TABLE #otherLOSprobDist
IF OBJECT_ID('tempdb..#otherPredArrDOW') IS NOT NULL DROP TABLE #otherPredArrDOW
IF OBJECT_ID('tempdb..#otherPredArr') IS NOT NULL DROP TABLE #otherPredArr
IF OBJECT_ID('tempdb..#otherFinalScaffold') IS NOT NULL DROP TABLE #otherFinalScaffold
--03 20 2020----------------------------------------------------------------------------------
--OB--
IF OBJECT_ID('tempdb..#preNatal') IS NOT NULL DROP TABLE #preNatal
IF OBJECT_ID('tempdb..#OBpop') IS NOT NULL DROP TABLE #OBpop
IF OBJECT_ID('tempdb..#obLOSprobDist') IS NOT NULL DROP TABLE #obLOSprobDist
IF OBJECT_ID('tempdb..#obExpArr0') IS NOT NULL DROP TABLE #obExpArr0
IF OBJECT_ID('tempdb..#obExpArr') IS NOT NULL DROP TABLE #obExpArr
IF OBJECT_ID('tempdb..#preNatalMaxDates') IS NOT NULL DROP TABLE #preNatalMaxDates
IF OBJECT_ID('tempdb..#preNatalByPt') IS NOT NULL DROP TABLE #preNatalByPt
IF OBJECT_ID('tempdb..#obFinalScaffold') IS NOT NULL DROP TABLE #obFinalScaffold
IF OBJECT_ID('tempdb..#obPredArrDOW') IS NOT NULL DROP TABLE #obPredArrDOW
IF OBJECT_ID('tempdb..#obPredArr') IS NOT NULL DROP TABLE #obPredArr
IF OBJECT_ID('tempdb..#obOtherFinalScaffold') IS NOT NULL DROP TABLE #obOtherFinalScaffold
--Surgical admits--
IF OBJECT_ID('tempdb..#surgicalBuffer') IS NOT NULL DROP TABLE #surgicalBuffer
IF OBJECT_ID('tempdb..#surgicalPop') IS NOT NULL DROP TABLE #surgicalPop
IF OBJECT_ID('tempdb..#surgicalLOSprobDist') IS NOT NULL DROP TABLE #surgicalLOSprobDist
IF OBJECT_ID('tempdb..#surgicalExpArr') IS NOT NULL DROP TABLE #surgicalExpArr
IF OBJECT_ID('tempdb..#surgicalFinalScaffold') IS NOT NULL DROP TABLE #surgicalFinalScaffold
IF OBJECT_ID('tempdb..#surgicalSchedule') IS NOT NULL DROP TABLE #surgicalSchedule
IF OBJECT_ID('tempdb..#surgicalSchedule0') IS NOT NULL DROP TABLE #surgicalSchedule0
--03 23 2020----------------------------------------------------------------------------------
--Neonates--
IF OBJECT_ID('tempdb..#neonatePop') IS NOT NULL DROP TABLE #neonatePop
IF OBJECT_ID('tempdb..#neonateLOSprobDist') IS NOT NULL DROP TABLE #neonateLOSprobDist
IF OBJECT_ID('tempdb..#neonateExpArr') IS NOT NULL DROP TABLE #neonateExpArr
IF OBJECT_ID('tempdb..#expNeonatesPerDelivery') IS NOT NULL DROP TABLE #expNeonatesPerDelivery
IF OBJECT_ID('tempdb..#expNeonatesPerDeliveryByLocation') IS NOT NULL DROP TABLE #expNeonatesPerDeliveryByLocation
IF OBJECT_ID('tempdb..#neonateExpArr') IS NOT NULL DROP TABLE #neonateExpArr
IF OBJECT_ID('tempdb..#neonateFinalScaffold') IS NOT NULL DROP TABLE #neonateFinalScaffold
IF OBJECT_ID('tempdb..#neonatePredArrDOW') IS NOT NULL DROP TABLE #neonatePredArrDOW
IF OBJECT_ID('tempdb..#neonatePredArr') IS NOT NULL DROP TABLE #neonatePredArr
IF OBJECT_ID('tempdb..#neonateOtherFinalScaffold') IS NOT NULL DROP TABLE #neonateOtherFinalScaffold
--04 01 2020----------------------------------------------------------------------------------
--should really reorder this whole thing...
IF OBJECT_ID('tempdb..#histCensus') IS NOT NULL DROP TABLE #histCensus

--IF OBJECT_ID('tempdb..#') IS NOT NULL DROP TABLE #




--*****************************************************************************************--------
--03 17 2020 build initial tables to help throughout-----------------------------------------------
---------------------------------------------------------------------------------------------------
--*****************************************************************************************--------




--List of A Codes---------------------------------------
select
         HOSP_SERV_C
       , NAME AS PATIENT_SERVICE_NAME
       , ABBR AS PATIENT_SERVICE_ABBR
       , RTRIM(SUBSTRING(abbr,1, PATINDEX('% _[0-9][0-9][0-9]%', abbr))) as PATIENT_SERVICE_GRP
INTO #ACodeList
from ZC_PAT_SERVICE
where PATINDEX('% A[0-9][0-9][0-9]%', abbr) <> 0
--Build Scaffold table---------------------------------------
select
       dd.DAY_NUM_OF_YEAR-1 AS day_num -- 0 to 365, 0 = yesterday, which is latest data
INTO #scaffold
from CLARITY_REPORTING..DIM_DATE dd
where dd.CAL_YEAR = '2020' --AND dd.DAY_NUM_OF_YEAR < 32
--Date lookup table--------------------------
SELECT
	CASE WHEN dt.WORKDAY_IND = 0 THEN 1 --group weekends & holidays
		WHEN dt.WORKDAY_IND = 1 AND dt.HOLIDAY_OBSERVED_IND = 1 THEN 1 --group weekends & holidays
		ELSE DATEPART(WEEKDAY, dt.DAY_DATE) --Su = 1, Sa = 7, so expect 2-6 for M-F
		END DOW_adjusted
	, dt.DAY_DATE
INTO #dateTablePre1
FROM CLARITY_REPORTING..dim_date_v2 dt
where dt.DAY_DATE >= @historicalStartDate
	and dt.DAY_DATE <= dateadd(day, @daysToPredictForwardOB, @endDate)
--get ready to take better averages for sparse arrival streams
SELECT
	dt.DOW_adjusted
	, COUNT(* ) AS lookback_days_for_DOW
INTO #dateTablePre2
FROM #dateTablePre1 dt
WHERE dt.DAY_DATE > DATEADD(DAY, -@predictLookbackWindow -1, @endDate)
	AND dt.DAY_DATE < @endDate
GROUP BY dt.DOW_adjusted
--better date table
select
	dt.*
	, dt2.lookback_days_for_DOW
INTO #dateTable
from #dateTablePre1 dt
JOIN #dateTablePre2 dt2 on dt.DOW_adjusted = dt2.DOW_adjusted

--main table of encounters. Used throughout---------------------------------------
select
       hsp.PAT_ENC_CSN_ID, hsp.PAT_ID
       , acode.PATIENT_SERVICE_GRP
       , acode.PATIENT_SERVICE_NAME
       , hsp.HOSP_ADMSN_TIME, hsp.HOSP_DISCH_TIME
       , DATEDIFF(DAY, hsp.HOSP_ADMSN_TIME, hsp.HOSP_DISCH_TIME) AS LOS
	   , hsp.ED_DEPARTURE_TIME
	   , hsp.ACUITY_LEVEL_C
	   , hsp.ADT_PAT_CLASS_C
	   , hsp.HSP_ACCOUNT_ID
	   , hsp.HOSP_SERV_C
	   , dep.DEPARTMENT_NAME
into #allEncounters
from PAT_ENC_HSP hsp
JOIN CLARITY..CLARITY_DEP dep
   ON dep.DEPARTMENT_ID = hsp.DEPARTMENT_ID
join clarity..ZC_DEP_RPT_GRP_15 grouper15
    ON grouper15.RPT_GRP_FIFTEEN_C = dep.RPT_GRP_FIFTEEN_C
left join #ACodeList acode
	on acode.HOSP_SERV_C = hsp.HOSP_SERV_C
where hsp.ADT_SERV_AREA_ID = 10 -- UIHC Hospital
	and hsp.ADMIT_CONF_STAT_C in (1) -- Confirmed (!or Completed)
	and hsp.ADT_PATIENT_STAT_C in (2, 3) -- Admission or Discharge
	--and hsp.ADT_PAT_CLASS_C not in (2, 6, 10, 30) --used to do this, before using Grouper 15.  2 hospital outpatient surg, 6 emergency, 10 observation, 30 outpatient in bed
	AND grouper15.NAME IS NOT NULL --look for inpatient grouper (grouper 15)
	and (hsp.HOSP_DISCH_TIME >= @historicalStartDate
		or hsp.HOSP_DISCH_TIME is NULL) --discharged within our timeframe (after StartDate) or still admitted

--currently admitted population pop---------------------------------------
SELECT
	hsp.PAT_ENC_CSN_ID, hsp.HSP_ACCOUNT_ID, hsp.PAT_ID
	, convert(date, hsp.HOSP_ADMSN_TIME, 101) AS admit_date
	, DATEDIFF(DAY, convert(date, hsp.HOSP_ADMSN_TIME, 101), @endDate)-1 AS days_into_admission
	, hsp.PATIENT_SERVICE_GRP
	, hsp.PATIENT_SERVICE_NAME
INTO #currentAdmitPop
from #allEncounters hsp --based on CLARITY..PAT_ENC_HSP, but nicely pre-filtered. Helps be consistent
WHERE hsp.HOSP_ADMSN_TIME < @endDate --admitted before end date
	AND (hsp.HOSP_DISCH_TIME is NULL --still here
		OR hsp.HOSP_DISCH_TIME >= @endDate) --or were still here on end date





--*****************************************************************************************--------
--03 20 2020 jeff add OB---------------------------------------------------------------------------
---------based on code from Joe--------------------------------------------------------------------
--*****************************************************************************************--------





--get list of prenatal visits, to help identify expected OB patients---
SELECT
	enc.PAT_ENC_CSN_ID
	, enc.CONTACT_DATE
	, enc.PAT_ID
	, COALESCE(MAX(OB_HSB_DATING.OB_DT_EDDUSR_DT), MAX(OB_HSB_DATING.OB_DT_EDDSYS_DT)) AS exp_delivery_dt
	, MAX(apptStatus.NAME) [Appt Status]
	, MAX(OB_HSB_DATING.OB_DT_WRKEDD_YN) OB_DT_WRKEDD_YN --most recent estimated delivery date
	, MAX(CASE WHEN ser.PROV_NAME LIKE '%HROB%' THEN 'HROB' ELSE NULL END) HROB_Flag --"High Risk OB"
INTO #preNatal
FROM	   clarity..PAT_ENC enc
INNER JOIN clarity..EPISODE_LINK	link ON enc.PAT_ENC_CSN_ID = link.PAT_ENC_CSN_ID
INNER JOIN clarity..EPISODE episode	ON link.EPISODE_ID = EPISODE.EPISODE_ID --link encounters to episodes
INNER JOIN clarity..OB_HSB_DATING OB_HSB_DATING	ON EPISODE.EPISODE_ID = OB_HSB_DATING.SUMMARY_BLOCK_ID --OB exp delivery dates. effectively limits episodes to be only OB episodes.
INNER JOIN clarity..ZC_APPT_STATUS apptStatus	ON enc.APPT_STATUS_C = apptStatus.APPT_STATUS_C
INNER JOIN clarity..CLARITY_DEP dep	ON enc.EFFECTIVE_DEPT_ID = dep.DEPARTMENT_ID
INNER JOIN clarity..CLARITY_SER ser	ON enc.VISIT_PROV_ID = ser.PROV_ID
WHERE	   OB_HSB_DATING.OB_DT_WRKEDD_YN = 'Y' --only include current delivery date estimate
	AND dep.SERV_AREA_ID = 10
	AND enc.APPT_STATUS_C IN (2, 6) --EPT 7020. 2 = completed; 6 = arrived
	AND enc.CONTACT_DATE >= @historicalStartDate
	and enc.CONTACT_DATE <= @endDate
GROUP BY enc.PAT_ENC_CSN_ID, enc.CONTACT_DATE, enc.PAT_ID
--figure out most recent pre-natal contact---------------------------------------
SELECT
	PAT_ID, MAX(CONTACT_DATE) AS max_prenatal_date
INTO #preNatalMaxDates
FROM #preNatal
GROUP BY PAT_ID
--group pre-natal contacts to pt level-------------------------------------------
SELECT
	main.PAT_ID
	, COALESCE(MAX(main.HROB_Flag), 'Normal') Prenatal_Status
	, MAX(CASE WHEN maxEnc.max_prenatal_date = main.CONTACT_DATE THEN main.exp_delivery_dt
		ELSE NULL END) exp_delivery_dt
INTO #preNatalByPt
FROM #preNatal main
JOIN #preNatalMaxDates maxEnc	ON maxEnc.PAT_ID = main.PAT_ID
GROUP BY main.PAT_ID
--get OB encounters, current and historical---------------------------------------------
SELECT
	encHsp.PAT_ENC_CSN_ID
	, encHsp.HOSP_ADMSN_TIME
	, encHsp.HOSP_DISCH_TIME
	, encHsp.LOS, encHsp.PAT_ID
	, MAX(obHsbDelivery.OB_DEL_BIRTH_DTTM) OB_DEL_BIRTH_DTTM --delivery time, if applicable
	, MAX(deliveryTypeLookup.NAME) deliveryType
	, COALESCE(MAX(encPreNatal.Prenatal_Status), 'No UIHC Prenatal Care') OB_Status --high risk, normal, no UIHC
INTO #OBpop
FROM #allEncounters encHsp
LEFT JOIN CLARITY..OB_HSB_DELIVERY obHsbDelivery	--deliveries
	ON encHsp.PAT_ENC_CSN_ID = obHsbDelivery.DELIVERY_DATE_CSN
LEFT JOIN CLARITY..ZC_DELIVERY_TYPE deliveryTypeLookup
	ON obHsbDelivery.OB_DEL_DELIV_METH_C = deliveryTypeLookup.DELIVERY_TYPE_C
LEFT JOIN  #preNatalByPt encPreNatal --any prenatal care at UIHC
	ON encHsp.PAT_ID = encPreNatal.PAT_ID
WHERE encHsp.HOSP_ADMSN_TIME >= DATEADD(day, 300, @historicalStartDate) --allow for prenatal visits to build up fully (e.g. full length of pregnancy)
	AND (deliveryTypeLookup.NAME IS NOT NULL --delivered (this also includes miscarriages, etc - these have delivery statuses as well)
		OR (encHsp.DEPARTMENT_NAME = 'LDR' AND encHsp.HOSP_DISCH_TIME IS NULL)) --currently in LDR
GROUP BY encHsp.PAT_ENC_CSN_ID, encHsp.HOSP_ADMSN_TIME, encHsp.HOSP_DISCH_TIME
	, encHsp.LOS, encHsp.PAT_ID
--LOS Prob dist OB---------------------------------------
SELECT
       tmp.OB_Status, scaffold.day_num
       , COUNT(*) denominator, SUM(CASE WHEN tmp.LOS > scaffold.day_num THEN 1 ELSE 0 END) numerator --use greater than to align with #scaffold. e.g. 1 day LOS will only show up on day 0, which is really the first day.
       , CAST(SUM(CASE WHEN tmp.LOS > scaffold.day_num THEN 1 ELSE 0 END) AS FLOAT) / CAST(COUNT(*) AS FLOAT) probability
INTO #obLOSprobDist
FROM #OBpop tmp
JOIN #scaffold scaffold       ON scaffold.day_num <= @daysToPredictForwardOB
WHERE tmp.HOSP_DISCH_TIME IS NOT NULL --only discharges
	AND tmp.HOSP_DISCH_TIME >= DATEADD(YEAR, 1, @historicalStartDate) --allow for admits to fully hit their cycle, should still be enough data
	AND tmp.HOSP_DISCH_TIME < @endDate
GROUP BY tmp.OB_Status, scaffold.day_num
--Forecast expected OB arrivals ---------------------------------------
SELECT
	tmp.PAT_ID
	, tmp.exp_delivery_dt
	, tmp.Prenatal_Status AS OB_Status
INTO #obExpArr0
FROM #preNatalByPt tmp --patients receiving UIHC prenatal care
LEFT JOIN #OBpop deliveries --only want patients who haven't delivered in last 300 days (max gestational period), so left join to patients who HAVE
	ON deliveries.PAT_ID = tmp.PAT_ID
	AND DATEDIFF(DAY, deliveries.OB_DEL_BIRTH_DTTM, @endDate) <= 300
	AND DATEDIFF(DAY, deliveries.OB_DEL_BIRTH_DTTM, @endDate) >= 0
LEFT JOIN #currentAdmitPop currPop on currPop.PAT_ID = tmp.PAT_ID --don't want already admitted pts
WHERE tmp.exp_delivery_dt >= @endDate
	AND tmp.exp_delivery_dt <= DATEADD(DAY, @daysToPredictForwardOB, @endDate)
	AND deliveries.PAT_ENC_CSN_ID IS NULL --haven't showed up for delivery yet
	AND currPop.PAT_ID IS NULL --not already admitted
--Group expected OB arrivals ---------------------------------------
SELECT
	COUNT(DISTINCT tmp.PAT_ID) AS exp_OB_admits
	--, tmp.exp_delivery_dt
	, tmp.OB_Status
	, DATEDIFF(DAY, @endDate, tmp.exp_delivery_dt) + 1 day_num
	, 'OB_Expected_Admits_' + tmp.OB_Status + '_day_'
		+ CAST(DATEDIFF(DAY, @endDate, tmp.exp_delivery_dt) + 1 AS VARCHAR(10)) AS cat_id -- e.g. 'OB_Expected_Admits_HROB_day_3'
INTO #obExpArr
FROM #obExpArr0 tmp
GROUP BY tmp.OB_Status, tmp.exp_delivery_dt
--scaffold to include decay rate-------------------------------------
SELECT
	scaffold.cat_ID, scaffold.day_num AS arr_day, prob.day_num AS post_arr_day
	, scaffold.day_num + prob.day_num AS day_num_actual
	, dateadd(day, scaffold.day_num + prob.day_num -1, @endDate) as day_date
	, scaffold.exp_OB_admits
	--, prob.probability
	, prob.probability * scaffold.exp_OB_admits AS predCensus
	, prob.OB_Status
INTO #obFinalScaffold
FROM #obExpArr scaffold
JOIN #obLOSprobDist prob	ON prob.OB_Status = scaffold.OB_Status
WHERE scaffold.day_num + prob.day_num <= @daysToPredictForwardOB
--predict non-UIHC OB arrivals for each DOW---------------------------------------
SELECT
	dt.DOW_adjusted
	--, COUNT(*) AS tot_arr, COUNT(DISTINCT dt.DAY_DATE) AS num_days
	, CAST(COUNT(*) AS float) / CAST(MAX(dt.lookback_days_for_DOW) AS FLOAT) AS pred_admits
INTO #obPredArrDOW
FROM #OBpop pop --current and historical OB encounters
JOIN #dateTable dt	ON dt.DAY_DATE = convert(date, pop.HOSP_ADMSN_TIME, 101)
WHERE pop.HOSP_ADMSN_TIME <  @endDate
	AND pop.HOSP_ADMSN_TIME >= DATEADD(DAY, -@predictLookbackWindow, @endDate)
	AND pop.OB_Status = 'No UIHC Prenatal Care'
GROUP BY dt.DOW_adjusted --Su = 1, Sa = 7, so expect 2-6 for M-F
--Scaffold Predicted Other OB Admits to come every day in future---------------------------------------
SELECT
	scaffold.day_num
	--, dt.DAY_DATE , predict.DOW_adjusted
	, predict.pred_admits
	, 'OB_No_UIHC_Prenatal_Care_DAY_' + CAST(scaffold.day_num AS VARCHAR(10)) AS cat_ID
INTO #obPredArr
FROM #scaffold scaffold
JOIN #dateTable dt
	ON dt.DAY_DATE = DATEADD(DAY, scaffold.day_num - 1, @endDate)
JOIN #obPredArrDOW predict
	ON predict.DOW_adjusted = dt.DOW_adjusted
WHERE scaffold.day_num > 0 -- day 0 is yesterday / current pop. arrivals arrive between midnight on day 0 and midnight on day 1, so start on day 1
	AND scaffold.day_num <= @daysToPredictForwardOB --don't need that much data
--ORDER BY scaffold.day_num
--Predicted Other OB Admits merged into full Scaffold, eg predictions for every day, with decay curve plotted out------------------------------
SELECT
	scaffold.cat_ID , scaffold.day_num AS arr_day, prob.day_num AS post_arr_day
	, scaffold.day_num + prob.day_num AS day_num_actual
	, dateadd(day, scaffold.day_num + prob.day_num -1, @endDate) as day_date
	--, scaffold.pred_admits, prob.probability
	, prob.probability * scaffold.pred_admits AS predCensus
	, prob.OB_Status
INTO #obOtherFinalScaffold
FROM #obPredArr scaffold
JOIN #obLOSprobDist prob	ON prob.OB_Status = 'No UIHC Prenatal Care'
WHERE scaffold.day_num + prob.day_num <= @daysToPredictForwardOB
--ORDER BY scaffold.day_num, prob.day_num





--*****************************************************************************************--------
--03 23 2020 Jeff add Neonates---------------------------------------------------------------------
--------------based on code from Joe---------------------------------------------------------------
--*****************************************************************************************--------





--build population
select  --top 100
	main.pat_id, main.pat_enc_CSN_ID
	, main.HOSP_ADMSN_TIME, main.HOSP_DISCH_TIME, main.LOS
	, COALESCE(ob.OB_status, 'Not birth encounter') as neonateStatus
	, main.department_name
	, ob.pat_enc_csn_id mom_CSN
INTO #neonatePop
from #allEncounters main
LEFT join clarity..patient pt  on pt.pat_id = main.pat_id
LEFT JOIN #OBpop ob on pt.mother_pat_id = ob.pat_id
	and datediff(day, ob.OB_DEL_BIRTH_DTTM, main.hosp_admsn_time) <=1
	and datediff(day, main.hosp_admsn_time, ob.OB_DEL_BIRTH_DTTM) <=1
WHERE main.department_name in ('NNSY', 'SFCH06 NIC2', 'NIC1', 'NNY2')
	AND (main.HOSP_DISCH_TIME IS NULL
		OR main.HOSP_ADMSN_TIME >= DATEADD(year, 1, @historicalStartDate))
--LOS Prob dist Neonate---------------------------------------
SELECT
       tmp.neonateStatus, scaffold.day_num, tmp.department_name
       , COUNT(*) denominator, SUM(CASE WHEN tmp.LOS > scaffold.day_num THEN 1 ELSE 0 END) numerator --use greater than to align with #scaffold. e.g. 1 day LOS will only show up on day 0, which is really the first day.
       , CAST(SUM(CASE WHEN tmp.LOS > scaffold.day_num THEN 1 ELSE 0 END) AS FLOAT) / CAST(COUNT(*) AS FLOAT) probability
INTO #neonateLOSprobDist
FROM #neonatePop tmp
JOIN #scaffold scaffold       ON scaffold.day_num <= @daysToPredictForward
WHERE tmp.HOSP_DISCH_TIME IS NOT NULL --only discharges
	AND tmp.HOSP_DISCH_TIME >= DATEADD(YEAR, 1, @historicalStartDate) --allow for admits to fully hit their cycle, should still be enough data
	AND tmp.HOSP_DISCH_TIME < @endDate
GROUP BY tmp.neonateStatus, scaffold.day_num, tmp.department_name
--OB to neonate admit pct--------------------------
SELECT
	ob.OB_status
	, COUNT( distinct neo.pat_enc_csn_id)  as total_babies_by_status
	, COUNT( distinct ob.pat_enc_csn_id)  as total_moms_by_status
	, CAST(COUNT( distinct neo.pat_enc_csn_id) as float) / CAST(COUNT (distinct ob.pat_enc_CSN_ID) as float) babies_per_mom_admit
INTO #expNeonatesPerDelivery
FROM #OBpop ob
LEFT JOIN  #neonatePop neo ON neo.mom_CSN = ob.pat_enc_csn_id
group by ob.OB_status
--expected neonates per OB delivery, by location--
select
	neo.department_name
	, expNeo.OB_status
	, CAST(COUNT(DISTINCT neo.pat_enc_csn_id) AS FLOAT) / CAST(MAX(total_moms_by_status) AS FLOAT) exp_babies_per_OB_adm
INTO #expNeonatesPerDeliveryByLocation
from #neonatePop neo
JOIN #expNeonatesPerDelivery expNeo on neo.neonateStatus = expNeo.OB_status
WHERE expNeo.OB_Status in ('HROB', 'Normal') --non-UIHC and non-delivery encounters will be handled separately
GROUP BY neo.department_name, expNeo.OB_status
--forecast expected neonate arrivals ---------------------------------------
select
	CAST(obExp.exp_OB_admits as float) * expNeo.exp_babies_per_OB_adm as exp_neonates
	, obExp.OB_Status, obExp.day_num, expNeo.department_name
	, 'Neonate_UIHC_' + obExp.OB_Status + '_' + expNeo.department_name + '_DAY_' +  CAST(obExp.day_num as varchar(10)) cat_ID
INTO #neonateExpArr
FROM #obExpArr obExp
JOIN #expNeonatesPerDeliveryByLocation expNeo on expNeo.OB_status = obExp.OB_status
--scaffold to include decay rate-------------------------------------
SELECT
	scaffold.cat_ID , scaffold.day_num AS arr_day, prob.day_num AS post_arr_day
	, scaffold.day_num + prob.day_num AS day_num_actual
	, dateadd(day, scaffold.day_num + prob.day_num -1, @endDate) as day_date
	--, scaffold.exp_neonates, prob.probability
	, prob.probability * scaffold.exp_neonates AS predCensus
	, prob.neonateStatus, prob.department_name
INTO #neonateFinalScaffold
FROM #neonateExpArr scaffold
JOIN #neonateLOSprobDist prob
	ON prob.neonateStatus = scaffold.OB_Status
	AND prob.department_name = scaffold.department_name
WHERE scaffold.day_num + prob.day_num <= @daysToPredictForward



--predict non-UIHC neonate arrivals for each DOW---------------------------------------
SELECT
	dt.DOW_adjusted, pop.department_name, pop.neonateStatus
	--, COUNT(*) AS tot_arr, COUNT(DISTINCT dt.DAY_DATE) AS num_days
	, CAST(COUNT(*) AS float) / CAST(MAX(lookback_days_for_DOW) AS float) AS pred_admits
INTO #neonatePredArrDOW
FROM #neonatePop pop
JOIN #dateTable dt	ON dt.DAY_DATE = convert(date, pop.HOSP_ADMSN_TIME, 101)
	AND dt.DAY_DATE <= dateadd(day, @daysToPredictForward, @endDate)
WHERE pop.HOSP_ADMSN_TIME <  @endDate --ed departure date = Inpt admit date for ED admits
	AND pop.HOSP_ADMSN_TIME >= DATEADD(DAY, -@predictLookbackWindow, @endDate)
	AND pop.neonateStatus NOT IN ('HROB', 'Normal') --deal with these other statuses separately
GROUP BY dt.DOW_adjusted, pop.department_name, pop.neonateStatus --Su = 1, Sa = 7, so expect 2-6 for M-F
--Scaffold Predicted Other neonate Admits to come every day in future---------------------------------------
SELECT
	scaffold.day_num, predict.department_name, predict.neonateStatus
	--, dt.DAY_DATE , predict.DOW_adjusted
	, predict.pred_admits
	, 'Neonate_UIHC_' + predict.neonateStatus + '_' + predict.department_name + '_DAY_' +  CAST(scaffold.day_num as varchar(10)) cat_ID
INTO #neonatePredArr
FROM #scaffold scaffold
JOIN #dateTable dt
	ON dt.DAY_DATE = DATEADD(DAY, scaffold.day_num - 1, @endDate)
	AND dt.DAY_DATE <= dateadd(day, @daysToPredictForward, @endDate)
JOIN #neonatePredArrDOW predict
	ON predict.DOW_adjusted = dt.DOW_adjusted
WHERE scaffold.day_num > 0 -- day 0 is yesterday / current pop. arrivals arrive between midnight on day 0 and midnight on day 1, so start on day 1
	AND scaffold.day_num <= @daysToPredictForward --don't need that much data
--ORDER BY scaffold.day_num
--Predicted Other neonate Admits merged into full Scaffold, eg predictions for every day, with decay curve plotted out------------------------------
SELECT
	scaffold.cat_ID , scaffold.day_num AS arr_day, prob.day_num AS post_arr_day
	, scaffold.day_num + prob.day_num AS day_num_actual
	, dateadd(day, scaffold.day_num + prob.day_num -1, @endDate) as day_date
	--, scaffold.pred_admits, prob.probability
	, prob.probability * scaffold.pred_admits AS predCensus
	, prob.neonateStatus, prob.department_name
INTO #neonateOtherFinalScaffold
FROM #neonatePredArr scaffold
JOIN #neonateLOSprobDist prob	ON prob.neonateStatus = scaffold.neonateStatus
	AND prob.department_name = scaffold.department_name
WHERE scaffold.day_num + prob.day_num <= @daysToPredictForward
--ORDER BY scaffold.day_num, prob.day_num






--*****************************************************************************************--------
--03 20 2020 tyler add surgical admits-------------------------------------------------------------
---------------------------------------------------------------------------------------------------
--*****************************************************************************************--------






--get a list of surgeries----------------------------------------------------------------------
--  only look at surgeries that were actually done, and only if it was scheduled prior to admission
--  end result: list of performed surgeries that were scheduled prior to admission
select
	hsp.PAT_ENC_CSN_ID
	, rank() over (partition by hsp.pat_enc_csn_id
		order by SURGICAL_PROCEDURE_LOG.SURGERY_DATE, enc.entry_time
			, SURGICAL_PROCEDURE_LOG.LOG_ID ) as ENTRY_TIME_RANK
	, primaryProcLookup.PROC_NAME AS Primary_Procedure
	, OR_LOG_LOC.LOC_NAME as surgical_location
INTO #surgicalBuffer
FROM  CLARITY..ZC_OR_STATUS  OR_STATUS
RIGHT OUTER JOIN CLARITY..OR_LOG  SURGICAL_PROCEDURE_LOG
	ON (SURGICAL_PROCEDURE_LOG.STATUS_C=OR_STATUS.STATUS_C)
JOIN CLARITY..OR_LOG_VIRTUAL virtual ON virtual.LOG_ID = SURGICAL_PROCEDURE_LOG.LOG_ID
JOIN CLARITY..OR_PROC primaryProcLookup ON primaryProcLookup.OR_PROC_ID = virtual.PRIMARY_PROC_ID
JOIN CLARITY..CLARITY_LOC  OR_LOG_LOC ON (SURGICAL_PROCEDURE_LOG.LOC_ID=OR_LOG_LOC.LOC_ID)
JOIN CLARITY..PAT_OR_ADM_LINK admLink on admLink.OR_CASELOG_ID = SURGICAL_PROCEDURE_LOG.LOG_ID
JOIN CLARITY..PAT_ENC_HSP hsp
	on hsp.PAT_ENC_CSN_ID = (coalesce(admLink.OR_LINK_CSN, admLink.pat_enc_csn_id))
JOIN CLARITY..PAT_ENC enc on enc.PAT_ENC_CSN_ID = admLink.PAT_ENC_CSN_ID
WHERE OR_LOG_LOC.SERV_AREA_ID = 10
	and OR_LOG_LOC.LOC_NAME  in ('ASC','SFCH05 PERIOP','MAIN OR','Urology OR')
	and OR_STATUS.NAME IN ('Complete','Posted','Completed', 'Unposted')
	and SURGICAL_PROCEDURE_LOG.PROC_NOT_PERF_C IS NULL
	and SURGICAL_PROCEDURE_LOG.SURGERY_DATE >= @historicalStartDate
	AND HSP.ADMIT_CONF_STAT_C = 1
	AND HSP.ADT_PATIENT_STAT_C IN (2, 3)
	and enc.ENTRY_TIME < hsp.HOSP_ADMSN_TIME --entered before admitted. assumption is that the admission can then be considered to be for the surgery. Not perfect, but the best we have so far.
--surgical admits-------------------------------------------------------------
--  merge list of surgeries with list of All Discharges
--  only look at the first surgery on a CSN.
--  end result: list of CSNs w/ first scheduled performed surgery. No row if no surgery on CSN.
--  define a Surgical Admission as:
--		one having a surgery scheduled prior to admission
--		and not already classified otherwise

select
	Surg.PAT_ENC_CSN_ID
	, encHsp.PAT_ENC_CSN_ID as enc_hsp_CSN
	, encHsp.HOSP_ADMSN_TIME
	, encHsp.HOSP_DISCH_TIME
	, COALESCE(DATEDIFF(DAY, encHsp.HOSP_ADMSN_TIME, encHsp.HOSP_DISCH_TIME), 0) LOS
	, surg.Primary_Procedure
	, surg.surgical_location
into #surgicalPop
from #surgicalBuffer surg
--left join, to keep non-inpatient surgeries. this is necessary, as the future case log doesn't explicitly tell you which cases will be admitted
LEFT JOIN #allEncounters encHsp ON encHsp.PAT_ENC_CSN_ID = surg.PAT_ENC_CSN_ID
LEFT JOIN #OBpop ob	ON ob.PAT_ENC_CSN_ID = encHsp.PAT_ENC_CSN_ID
LEFT JOIN #neonatePop neo	on neo.PAT_ENC_CSN_ID = encHsp.PAT_ENC_CSN_ID
WHERE surg.ENTRY_TIME_RANK = 1 --only keep first scheduled surgery on an encounter
	AND ob.PAT_ENC_CSN_ID IS NULL --exclude previously defined cohorts
	and neo.PAT_ENC_CSN_ID IS NULL


--LOS Prob dist surgery---------------------------------------
--  based on historical discharges of surgical admissions...
--		what is the probability a patient will be here x days into their admission?
--		(based on Primary Procedure)
--  LOS can be 0 (i.e. for patients discharged same day),
--		so admit % is rolled up in this probability already.
SELECT
       tmp.Primary_Procedure, scaffold.day_num, tmp.surgical_location
       , COUNT(*) denominator, SUM(CASE WHEN tmp.LOS > scaffold.day_num THEN 1 ELSE 0 END) numerator --use greater than to align with #scaffold. e.g. 1 day LOS will only show up on day 0, which is really the first day.
       , CAST(SUM(CASE WHEN tmp.LOS > scaffold.day_num THEN 1 ELSE 0 END) AS FLOAT) / CAST(COUNT(*) AS FLOAT) probability
INTO #surgicalLOSprobDist
FROM #surgicalPop tmp
JOIN #scaffold scaffold
       ON scaffold.day_num <= @daysToPredictForward
WHERE tmp.HOSP_DISCH_TIME IS NOT NULL --only discharges
GROUP BY tmp.Primary_Procedure, scaffold.day_num, tmp.surgical_location

--Get OR schedule--------------------------------------------------------
--  look at OR Cases for patients not already admitted
--		may need to look at historical cancel rates and late-schedule rates
--			especially late-schedule rates right now.
--			Cancellations are in a very unusual period right now.
--		for now, assume the current schedule is what will happen.
select
	primaryProcLookup.PROC_NAME Primary_Procedure
	, orc.SURGERY_DATE
	, loc.LOC_NAME as surgical_location
	,  rank() over (partition by orc.PAT_ID
		order by orc.SURGERY_DATE, enc.entry_time
			, orc.LOG_ID ) as ENTRY_TIME_RANK
INTO #surgicalSchedule0
from OR_CASE orc
JOIN CLARITY..OR_CASE_ALL_PROC primaryProc
	ON primaryProc.OR_CASE_ID = orc.OR_CASE_ID
	AND primaryProc.LINE = 1 --get first listed procedure, which should be the primary procedure
JOIN CLARITY..OR_PROC primaryProcLookup ON primaryProcLookup.OR_PROC_ID = primaryProc.OR_PROC_ID
join CLARITY_LOC loc on loc.LOC_ID = orc.LOC_ID
left join OR_LOG orl on orl.LOG_ID = orc.OR_CASE_ID
LEFT JOIN CLARITY..PAT_OR_ADM_LINK admLink on admLink.OR_CASELOG_ID = orc.OR_CASE_ID
LEFT JOIN CLARITY..PAT_ENC_HSP hsp
	on hsp.PAT_ENC_CSN_ID = (coalesce(admLink.OR_LINK_CSN, admLink.pat_enc_csn_id))
LEFT JOIN CLARITY..PAT_ENC ENC ON ENC.PAT_ENC_CSN_ID = admLink.PAT_ENC_CSN_ID
left join ZC_PAT_CLASS patclass on patclass.ADT_PAT_CLASS_C = hsp.ADT_PAT_CLASS_C
left join ZC_OR_STATUS orStatus on orStatus.STATUS_C = orl.STATUS_C
left join ZC_OR_SCHED_STATUS schedStatus on schedStatus.SCHED_STATUS_C = orc.SCHED_STATUS_C
left join ZC_OR_PEND_STATUS pendStatus on pendStatus.OR_PEND_STATUS_C = orc.PEND_STATUS_C
LEFT JOIN CLARITY..ZC_OR_SERVICE  OR_SERVICE
	ON or_service.SERVICE_C = coalesce(orl.SERVICE_C, orc.SERVICE_C)
LEFT JOIN CLARITY_REPORTING..OR_SERVICE_GROUP  orServiceGrp
	ON orServiceGrp.SERVICE_C = coalesce(orl.SERVICE_C, orc.SERVICE_C)
LEFT JOIN #currentAdmitPop currPop on currPop.PAT_ID = orc.PAT_ID
LEFT JOIN #obExpArr0 obExp on obExp.PAT_ID = orc.PAT_ID
where loc.SERV_AREA_ID = 10
	and loc.LOC_NAME  in ('ASC','SFCH05 PERIOP','MAIN OR','Urology OR')
	AND orc.SCHED_STATUS_C IN (1, 3, 4, 8) -- 1: sched, 3: not sched, 4: missing info, 8: completed
	and orc.PAT_CLASS_C <> 9 -- patient class not inpatient
	and orc.SURGERY_DATE >= @historicalStartDate
	and orc.SURGERY_DATE <= dateadd(DAY, @daysToPredictForward, @endDate)
	and (hsp.hosp_admsn_time IS NULL OR hsp.hosp_admsn_time >= @endDate)
	and obExp.PAT_ID IS NULL --not an expected OB arrival
	and currPop.PAT_ID IS NULL --not already admitted

--group expected procedures
select
	sched.Primary_Procedure
	, sched.surgical_location
	, sched.SURGERY_DATE
	, count(*) as NUM_SCHEDULED
INTO #surgicalSchedule
from #surgicalSchedule0 sched
where ENTRY_TIME_RANK = 1
group by sched.Primary_Procedure, sched.SURGERY_DATE, sched.surgical_location

--forecast Periop arrivals ---------------------------------------
SELECT
	tmp.Primary_Procedure
	, tmp.surgical_location
	, CAST(SUM(tmp.NUM_SCHEDULED) AS FLOAT) AS exp_Surg_admits
	, tmp.SURGERY_DATE
	, DATEDIFF(DAY, @endDate, tmp.SURGERY_DATE) + 1 day_num
	, 'Periop_Expected_Admits_' + tmp.surgical_location + '_' + tmp.Primary_Procedure + '_day_'
		+ CAST(DATEDIFF(DAY, @endDate, tmp.SURGERY_DATE) + 1 AS VARCHAR(10)) AS cat_id
INTO #surgicalExpArr
FROM #surgicalSchedule tmp
WHERE tmp.SURGERY_DATE >= @endDate
	AND tmp.SURGERY_DATE <= DATEADD(DAY, @daysToPredictForward, @endDate)
GROUP BY tmp.Primary_Procedure, tmp.SURGERY_DATE, tmp.surgical_location

--forecast Periop Admits merged into full Scaffold, eg predictions for every day, with decay curve plotted out------------------------------
SELECT
	scaffold.cat_ID , scaffold.day_num AS arr_day, prob.day_num AS post_arr_day
	, scaffold.day_num + prob.day_num AS day_num_actual
	, scaffold.Primary_Procedure, scaffold.surgical_location
	, dateadd(day, scaffold.day_num + prob.day_num -1, @endDate) as day_date
	--, scaffold.exp_Surg_admits, prob.probability
	, prob.probability * scaffold.exp_Surg_admits AS predCensus
INTO #surgicalFinalScaffold
FROM #surgicalExpArr scaffold
JOIN #surgicalLOSprobDist prob
	ON prob.Primary_Procedure = scaffold.Primary_Procedure
	AND prob.surgical_location = scaffold.surgical_location
WHERE scaffold.day_num + prob.day_num <= @daysToPredictForward
--ORDER BY scaffold.day_num, prob.day_num





--*****************************************************************************************--------
--03 18 2020 Tyler add External Transfers----------------------------------------------------------
---------------------------------------------------------------------------------------------------
--*****************************************************************************************--------






/*Copyright (C) 2020-2020 UIHC Business Intelligence Group
********************************************************************************
.Title        requests
select * from ZC_NCS_TOPIC
select * from ZC_TC_TRANSFER_TYPE
select * from ZC_TC_REQUEST_STATUS
********************************************************************************
*/
select
  ncsBase.COMM_ID AS REQUEST_NCS
--, ncsBase.SUBJ_MEMBER_ID -- not sure (test patient is valid or subj is null)
--, ncsBase.REC_COMM_ORIGIN_C  -- 16 = transfer center
, ncsBase.ENTRY_DATE as REQUEST_DATE
, topic.NAME as REQUEST_TYPE
, transferType.NAME as TRANSFER_TYPE
, requestStatus.NAME as REQUEST_STATUS
, intake.ATCHMENT_PT_CSN_ID as INTAKE_CSN -- dont think this is needed but leaving it
, CASE WHEN ncsBase.TOPIC_C = '100002' THEN 1 ELSE 0 END direct_admit_flag

into #request
from CUST_SERVICE ncsBase
join CUST_SERVICE_TRANSFER request
	ON request.COMM_ID = ncsBase.COMM_ID -- include
left join ZC_TC_REQUEST_STATUS requestStatus
	on requestStatus.TC_REQUEST_STATUS_C = request.REQUEST_STATUS_C
LEFT JOIN ZC_NCS_TOPIC topic
	on topic.TOPIC_C = ncsBase.TOPIC_C -- include
LEFT JOIN ZC_TC_TRANSFER_TYPE transferType
	on transferType.TC_TRANSFER_TYPE_C = request.TRANSFER_TYPE_C -- include
LEFT JOIN CUST_SERV_ATCHMENT intake
	on intake.COMM_ID = ncsBase.COMM_ID and intake.ATCHMENT_TYPE_C = 22

where 1=1
and ncsBase.REC_COMM_ORIGIN_C = 16
and request.TRANSFER_REGION_ID = 1391
--and ncsBase.TOPIC_C = '100002' -- direct admits only
and request.REQUEST_STATUS_C = 4 -- completed requests only



/*Copyright (C) 2020-2020 UIHC Business Intelligence Group
********************************************************************************
.Title        request destination

********************************************************************************
*/

select
  ncsBase.COMM_ID as REQUEST_NCS
, target.ATCHMENT_NCS_ID as DESTINATION_NCS
, destHx.LINE
, EPIC_UTIL.EFN_UTC_TO_LOCAL(destHx.STATUS_UPDATE_UTC_DTTM) as STATUS_UPDATE_DTTM
, coalesce(dest.ATCHMENT_PT_CSN_ID, -1) as DESTINATION_CSN


, cst.REQUEST_STATUS_C
, destCst.REQUEST_STATUS_C AS DESTINATION_STATUS_C
, destAud.REQUEST_STATUS_C AS DESTINATION_AUDIT_STATUS_C
, target.ATCHMENT_RSN_C
, hsp.ADMIT_CONF_STAT_C -- 1 confirmed
, hsp.ADT_PATIENT_STAT_C -- 2 admit 3 discharge
, confStat.NAME as ADMIT_CONF_STAT
, patStat.NAME as ADT_PATIENT_STAT
, rank() over (partition by ncsbase.comm_id order by hsp.admit_conf_stat_c,
              case when hsp.adt_patient_stat_c in (2, 3) then 0 else hsp.adt_patient_stat_c end,
              destHx.STATUS_UPDATE_UTC_DTTM DESC,
              dest.ATCHMENT_PT_CSN_ID desc
              ) as MULTI_DESELECTOR

into #destination

from CUST_SERVICE ncsBase
join CUST_SERVICE_TRANSFER cst
	ON cst.COMM_ID = ncsBase.COMM_ID
join CUST_SERV_ATCHMENT target
	on target.COMM_ID = ncsBase.COMM_ID and target.ATCHMENT_TYPE_C = 21 -- 91383
left join CUST_SERV_ATCHMENT dest
	on dest.COMM_ID = target.ATCHMENT_NCS_ID
left join CUST_SERVICE_TRANSFER destCst
	on destCst.COMM_ID = target.ATCHMENT_NCS_ID
left join TC_REQUEST_STATUS_HX destAud
	on destAud.COMM_ID = target.ATCHMENT_NCS_ID
	and destAud.LINE = (select max(line) - 1
		from TC_REQUEST_STATUS_HX destmx
		where destmx.COMM_ID = destAud.COMM_ID)
left join TC_REQUEST_STATUS_HX destHx
	on destHx.COMM_ID = target.ATCHMENT_NCS_ID
	and destHx.LINE = (select max(line)
		from TC_REQUEST_STATUS_HX destmx
		where destmx.COMM_ID = destHx.COMM_ID)

left join PAT_ENC_HSP hsp on hsp.PAT_ENC_CSN_ID = dest.ATCHMENT_PT_CSN_ID
LEFT JOIN ZC_CONF_STAT confStat on confStat.ADMIT_CONF_STAT_C = hsp.ADMIT_CONF_STAT_C
left join ZC_PAT_STATUS patStat on patStat.ADT_PATIENT_STAT_C = hsp.ADT_PATIENT_STAT_C

where 1=1
and ncsBase.REC_COMM_ORIGIN_C = 16 -- 100713 tc requests
--and ncsBase.COMM_ID = '1257390' -- multiple csn on single dest ncs
--and ncsBase.COMM_ID = '1499324'

and (
	(cst.REQUEST_STATUS_C <> 6 and destCst.REQUEST_STATUS_C in (2, 4)) or
	(cst.REQUEST_STATUS_C = 6 and destAud.REQUEST_STATUS_C in (2, 4)) or
	(destAud.REQUEST_STATUS_C is null and cst.TRANSFER_REGION_ID is not null)
)



/*Copyright (C) 2020-2020 UIHC Business Intelligence Group
********************************************************************************
.Title        request admissions (direct admit)

********************************************************************************
*/
SELECT
	encHsp.PAT_ENC_CSN_ID
	, r.REQUEST_NCS
	, encHsp.HOSP_ADMSN_TIME
	, encHsp.HOSP_DISCH_TIME
	, r.REQUEST_TYPE
	, r.TRANSFER_TYPE
	, encHsp.LOS
	, r.direct_admit_flag
INTO #extTransferPop
FROM #request r
JOIN #destination d on d.REQUEST_NCS = r.REQUEST_NCS and d.MULTI_DESELECTOR = 1

JOIN #allEncounters encHsp --based on CLARITY..PAT_ENC_HSP, but nicely pre-filtered. Helps be consistent
	ON encHsp.PAT_ENC_CSN_ID = d.DESTINATION_CSN
LEFT JOIN #OBpop ob	ON ob.PAT_ENC_CSN_ID = encHsp.PAT_ENC_CSN_ID
LEFT JOIN #neonatePop neo	on neo.PAT_ENC_CSN_ID = encHsp.PAT_ENC_CSN_ID
LEFT JOIN #surgicalPop periop	ON periop.PAT_ENC_CSN_ID = encHsp.PAT_ENC_CSN_ID
WHERE ob.PAT_ENC_CSN_ID IS NULL --don't include OB here...
	and neo.PAT_ENC_CSN_ID IS NULL
	AND periop.PAT_ENC_CSN_ID IS NULL --not periop

-- probability
SELECT
       tmp.REQUEST_TYPE, tmp.TRANSFER_TYPE, scaffold.day_num
       , COUNT(*) denominator, SUM(CASE WHEN tmp.LOS > scaffold.day_num THEN 1 ELSE 0 END) numerator --use greater than to align with #scaffold. e.g. 1 day LOS will only show up on day 0, which is really the first day.
       , CAST(SUM(CASE WHEN tmp.LOS > scaffold.day_num THEN 1 ELSE 0 END) AS FLOAT) / CAST(COUNT(*) AS FLOAT) probability
INTO #directAdmitLOSprobDist
FROM #extTransferPop tmp
JOIN #scaffold scaffold
	ON scaffold.day_num <= @daysToPredictForward
WHERE tmp.HOSP_DISCH_TIME IS NOT NULL --only discharges
	AND tmp.direct_admit_flag = 1
GROUP BY tmp.REQUEST_TYPE, tmp.TRANSFER_TYPE, scaffold.day_num
--ORDER BY tmp.REQUEST_TYPE, tmp.TRANSFER_TYPE, scaffold.day_num
--Predict direct admit arrivals---------------------------------------
SELECT
                tmp.REQUEST_TYPE, tmp.TRANSFER_TYPE
                , dt.DOW_adjusted
                --, COUNT(*) AS tot_arr, COUNT(DISTINCT dt.DAY_DATE) AS num_days
                , CAST(COUNT(*) AS float) / CAST(MAX(dt.lookback_days_for_DOW) AS float) AS pred_DA_admits
INTO #directAdmitPredArrDOW
FROM #extTransferPop tmp
JOIN #dateTable dt
                ON dt.DAY_DATE = convert(date, tmp.HOSP_ADMSN_TIME, 101)
				AND dt.DAY_DATE <= dateadd(day, @daysToPredictForward, @endDate)
WHERE tmp.HOSP_ADMSN_TIME < @endDate --ed departure date = Inpt admit date for ED admits
                AND tmp.HOSP_ADMSN_TIME >= DATEADD(DAY, -@predictLookbackWindow, @endDate)
				AND tmp.direct_admit_flag = 1
GROUP BY tmp.REQUEST_TYPE, tmp.TRANSFER_TYPE, dt.DOW_adjusted

--Scaffold Predicted direct admit Admits to come every day in future---------------------------------------
SELECT
                scaffold.day_num --, dt.DAY_DATE, predict.DOW_adjusted
                , predict.REQUEST_TYPE
                , predict.TRANSFER_TYPE
                , predict.pred_DA_admits
                , 'DIRECT_ADMIT_GRP_' + COALESCE(predict.transfer_type,'NULL') + '_DAY_' + CAST(scaffold.day_num AS VARCHAR(10)) AS cat_ID
INTO #directAdmitPredArr
FROM #scaffold scaffold
JOIN #dateTable dt
                ON dt.DAY_DATE = DATEADD(DAY, scaffold.day_num - 1, @endDate)
				AND dt.DAY_DATE <= dateadd(day, @daysToPredictForward, @endDate)
JOIN #directAdmitPredArrDOW predict
                ON predict.DOW_adjusted = dt.DOW_adjusted
WHERE scaffold.day_num > 0 -- day 0 is yesterday / current pop. arrivals arrive between midnight on day 0 and midnight on day 1, so start on day 1
                AND scaffold.day_num <= @daysToPredictForward --don't need that much data
--ORDER BY scaffold.day_num

--Predicted Direct Admits merged into full Scaffold---------------------------------------
SELECT
	scaffold.cat_ID , scaffold.day_num AS arr_day, prob.day_num AS post_arr_day
	, scaffold.day_num + prob.day_num AS day_num_actual
	, dateadd(day, scaffold.day_num + prob.day_num -1, @endDate) as day_date
	, scaffold.REQUEST_TYPE, scaffold.TRANSFER_TYPE
	--, scaffold.pred_DA_admits, prob.probability
	, prob.probability * scaffold.pred_DA_admits AS predCensus
INTO #directAdmitFinalScaffold
FROM #directAdmitPredArr scaffold
JOIN #directAdmitLOSprobDist prob
	ON prob.REQUEST_TYPE = scaffold.REQUEST_TYPE
	AND prob.TRANSFER_TYPE = scaffold.TRANSFER_TYPE
WHERE scaffold.day_num + prob.day_num <= @daysToPredictForward
--ORDER BY scaffold.day_num, prob.day_num






--*****************************************************************************************--------
--03 18 2020 jeff add ED---------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
--*****************************************************************************************--------





--ED admits---------------------------------------
SELECT
	encHsp.PAT_ENC_CSN_ID
	, encHsp.ED_DEPARTURE_TIME
	, encHsp.HOSP_DISCH_TIME
	, CAST(encHsp.ACUITY_LEVEL_C AS VARCHAR(10)) + ': ' + acuity.NAME as ACUITY_LEVEL
	, encHsp.LOS
	, CASE WHEN extPop.PAT_ENC_CSN_ID IS NOT NULL THEN 'ED-to-ED Transfer'
		ELSE 'Not a transfer' end ED_to_ED_Transfer_Flag
INTO #EDpop
FROM CLARITY..ED_IEV_PAT_INFO eventLink
JOIN CLARITY..ED_IEV_EVENT_INFO eventTable
	ON eventTable.EVENT_ID = eventLink.EVENT_ID
	AND eventTable.EVENT_DEPT_ID = '10410001' -- events in emergency department
	AND (eventTable.EVENT_STATUS_C <> 2 OR eventTable.EVENT_STATUS_C IS NULL)
	AND eventTable.EVENT_TYPE = '65' -- IEV 30 only include ED admits
JOIN #allEncounters encHsp ON encHsp.PAT_ENC_CSN_ID = eventLink.PAT_ENC_CSN_ID --based on CLARITY..PAT_ENC_HSP, but nicely pre-filtered. Helps be consistent
left outer join ZC_ACUITY_LEVEL acuity	ON acuity.ACUITY_LEVEL_C = encHsp.ACUITY_LEVEL_C
LEFT JOIN #extTransferPop extPop	ON extPop.PAT_ENC_CSN_ID = encHsp.PAT_ENC_CSN_ID
LEFT JOIN #OBpop ob	ON ob.PAT_ENC_CSN_ID = encHsp.PAT_ENC_CSN_ID
LEFT JOIN #neonatePop neo	on neo.PAT_ENC_CSN_ID = encHsp.PAT_ENC_CSN_ID
LEFT JOIN #surgicalPop periop	ON periop.PAT_ENC_CSN_ID = encHsp.PAT_ENC_CSN_ID
WHERE ob.PAT_ENC_CSN_ID IS NULL --don't include OB here...
	and neo.PAT_ENC_CSN_ID IS NULL
	AND periop.PAT_ENC_CSN_ID IS NULL --not periop
	and (extPop.PAT_ENC_CSN_ID IS NULL OR extPop.direct_admit_flag = 0) --Don't want to double count Direct Admits. This shouldn't actually do anything, but better safe than sorry...

--Prob ED---------------------------------------
SELECT
       tmp.ACUITY_LEVEL, scaffold.day_num, tmp.ED_to_ED_Transfer_Flag
       , COUNT(*) denominator, SUM(CASE WHEN tmp.LOS > scaffold.day_num THEN 1 ELSE 0 END) numerator --use greater than to align with #scaffold. e.g. 1 day LOS will only show up on day 0, which is really the first day.
       , CAST(SUM(CASE WHEN tmp.LOS > scaffold.day_num THEN 1 ELSE 0 END) AS FLOAT) / CAST(COUNT(*) AS FLOAT) probability
INTO #edLOSprobDist
FROM #EDpop tmp
JOIN #scaffold scaffold
       ON scaffold.day_num <= @daysToPredictForward
WHERE tmp.HOSP_DISCH_TIME IS NOT NULL --only discharges
GROUP BY tmp.ED_to_ED_Transfer_Flag, tmp.ACUITY_LEVEL, scaffold.day_num
--ORDER BY tmp.ACUITY_LEVEL, tmp.ED_to_ED_Transfer_Flag, scaffold.day_num
--Predict ED arrivals for each DOW---------------------------------------
SELECT
	ed.ED_to_ED_Transfer_Flag, ed.ACUITY_LEVEL, dt.DOW_adjusted
	--, COUNT(*) AS tot_arr, COUNT(DISTINCT dt.DAY_DATE) AS num_days
	, CAST(COUNT(*) AS float) / CAST(MAX(dt.lookback_days_for_DOW) AS float) AS pred_ED_admits
INTO #edPredArrDOW
FROM #EDpop ed
JOIN #dateTable dt
	ON dt.DAY_DATE = convert(date, ed.ED_DEPARTURE_TIME, 101)
	AND dt.DAY_DATE <= dateadd(day, @daysToPredictForward, @endDate)
WHERE ed.ED_DEPARTURE_TIME < @endDate --ed departure date = Inpt admit date for ED admits
	AND ed.ED_DEPARTURE_TIME >= DATEADD(DAY, -@predictLookbackWindow, @endDate)
GROUP BY ed.ED_to_ED_Transfer_Flag, ed.ACUITY_LEVEL, dt.DOW_adjusted
--Scaffold Predicted ED Admits to come every day in future---------------------------------------
SELECT
	scaffold.day_num --, dt.DAY_DATE, predict.DOW_adjusted
	, predict.ACUITY_LEVEL, predict.ED_to_ED_Transfer_Flag
	, predict.pred_ED_admits
	, 'ED_ESI_' + COALESCE(predict.ACUITY_LEVEL,'NULL') + predict.ED_to_ED_Transfer_Flag + '_DAY_' + CAST(scaffold.day_num AS VARCHAR(10)) AS cat_ID
INTO #edPredArr
FROM #scaffold scaffold
JOIN #dateTable dt
	ON dt.DAY_DATE = DATEADD(DAY, scaffold.day_num - 1, @endDate)
	AND dt.DAY_DATE <= dateadd(day, @daysToPredictForward, @endDate)
JOIN #edPredArrDOW predict
	ON predict.DOW_adjusted = dt.DOW_adjusted
WHERE scaffold.day_num > 0 -- day 0 is yesterday / current pop. arrivals arrive between midnight on day 0 and midnight on day 1, so start on day 1
	AND scaffold.day_num <= @daysToPredictForward --don't need that much data
--ORDER BY scaffold.day_num
--Predicted ED Admits merged into full Scaffold, eg predictions for every day, with decay curve plotted out------------------------------
SELECT
	scaffold.cat_ID , scaffold.day_num AS arr_day, prob.day_num AS post_arr_day
	, scaffold.day_num + prob.day_num AS day_num_actual
	, dateadd(day, scaffold.day_num + prob.day_num -1, @endDate) as day_date
	, scaffold.ACUITY_LEVEL, scaffold.ED_to_ED_Transfer_Flag
	--, scaffold.pred_ED_admits, prob.probability
	, prob.probability * scaffold.pred_ED_admits AS predCensus
INTO #edFinalScaffold
FROM #edPredArr scaffold
JOIN #edLOSprobDist prob
	ON prob.ACUITY_LEVEL = scaffold.ACUITY_LEVEL
	AND prob.ED_to_ED_Transfer_Flag = scaffold.ED_to_ED_Transfer_Flag
WHERE scaffold.day_num + prob.day_num <= @daysToPredictForward
--ORDER BY scaffold.day_num, prob.day_num






--*****************************************************************************************--------
--03 19 2020 jeff add "Other"----------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
--*****************************************************************************************--------






SELECT
	encHsp.PAT_ENC_CSN_ID
	, encHsp.HOSP_ADMSN_TIME
	, encHsp.HOSP_DISCH_TIME
	, encHsp.PATIENT_SERVICE_GRP
    , encHsp.PATIENT_SERVICE_NAME
	, encHsp.LOS
INTO #otherPop
FROM #allEncounters encHsp --based on CLARITY..PAT_ENC_HSP, but nicely pre-filtered. Helps be consistent
LEFT JOIN #extTransferPop extPop
	ON extPop.PAT_ENC_CSN_ID = encHsp.PAT_ENC_CSN_ID
	--AND extpop.direct_admit_flag = 1 --only direct admits
LEFT JOIN #EDpop ed	ON ed.PAT_ENC_CSN_ID = encHsp.PAT_ENC_CSN_ID
LEFT JOIN #OBpop ob ON ob.PAT_ENC_CSN_ID = encHsp.PAT_ENC_CSN_ID
LEFT JOIN #neonatePop neo	on neo.PAT_ENC_CSN_ID = encHsp.PAT_ENC_CSN_ID
LEFT JOIN #surgicalPop periop	ON periop.PAT_ENC_CSN_ID = encHsp.PAT_ENC_CSN_ID
WHERE ob.PAT_ENC_CSN_ID IS NULL --don't include OB here...
	and neo.PAT_ENC_CSN_ID IS NULL
	AND ed.PAT_ENC_CSN_ID IS NULL --not ED arrival
	AND extPop.PAT_ENC_CSN_ID IS NULL -- not direct admit
	AND periop.PAT_ENC_CSN_ID IS NULL --not periop
	AND (encHSP.HOSP_DISCH_TIME IS NULL
		OR encHsp.HOSP_DISCH_TIME >= DATEADD(year, 1, @historicalStartDate)) --don't want old OB or neonates included in Other
--LOS Prob dist for "other" admits---------------------------------------
SELECT
		scaffold.day_num
       , COUNT(*) denominator, SUM(CASE WHEN tmp.LOS > scaffold.day_num THEN 1 ELSE 0 END) numerator --use greater than to align with #scaffold. e.g. 1 day LOS will only show up on day 0, which is really the first day.
       , CAST(SUM(CASE WHEN tmp.LOS > scaffold.day_num THEN 1 ELSE 0 END) AS FLOAT)
			/ CAST(COUNT(*) AS FLOAT) probability
INTO #otherLOSprobDist
FROM #otherPop tmp
JOIN #scaffold scaffold
       ON 1 = 1
WHERE tmp.HOSP_DISCH_TIME IS NOT NULL
	AND scaffold.day_num <= @daysToPredictForward
GROUP BY scaffold.day_num
--Predict "Other" arrivals for each DOW---------------------------------------
SELECT
	dt.DOW_adjusted
	--, COUNT(*) AS tot_arr, COUNT(DISTINCT dt.DAY_DATE) AS num_days
	, CAST(COUNT(*) AS float) / CAST(MAX(dt.lookback_days_for_DOW) AS float) AS pred_admits
INTO #otherPredArrDOW
FROM #otherPop pop
JOIN #dateTable dt
	ON dt.DAY_DATE = convert(date, pop.HOSP_ADMSN_TIME, 101)
	AND dt.DAY_DATE <= dateadd(day, @daysToPredictForward, @endDate)
WHERE pop.HOSP_ADMSN_TIME <  @endDate --ed departure date = Inpt admit date for ED admits
	AND pop.HOSP_ADMSN_TIME >= DATEADD(DAY, -@predictLookbackWindow, @endDate)
GROUP BY dt.DOW_adjusted
--Scaffold Predicted Other Admits to come every day in future---------------------------------------
SELECT
	scaffold.day_num
	--, dt.DAY_DATE, predict.DOW_adjusted
	, predict.pred_admits
	, 'OTHER_DAY_' + CAST(scaffold.day_num AS VARCHAR(10)) AS cat_ID
INTO #otherPredArr
FROM #scaffold scaffold
JOIN #dateTable dt
	ON dt.DAY_DATE = DATEADD(DAY, scaffold.day_num - 1, @endDate)
	AND dt.DAY_DATE <= dateadd(day, @daysToPredictForward, @endDate)
JOIN #otherPredArrDOW predict
	ON predict.DOW_adjusted = dt.DOW_adjusted
WHERE scaffold.day_num > 0 -- day 0 is yesterday / current pop. arrivals arrive between midnight on day 0 and midnight on day 1, so start on day 1
	AND scaffold.day_num <= @daysToPredictForward --don't need that much data
--ORDER BY scaffold.day_num
--Predicted Other Admits merged into full Scaffold, eg predictions for every day, with decay curve plotted out------------------------------
SELECT
	scaffold.cat_ID , scaffold.day_num AS arr_day, prob.day_num AS post_arr_day
	, scaffold.day_num + prob.day_num AS day_num_actual
	, dateadd(day, scaffold.day_num + prob.day_num -1, @endDate) as day_date
	--, scaffold.pred_admits, prob.probability
	, prob.probability * scaffold.pred_admits AS predCensus
INTO #otherFinalScaffold
FROM #otherPredArr scaffold
JOIN #otherLOSprobDist prob
	ON 1=1
WHERE scaffold.day_num + prob.day_num <= @daysToPredictForward
--ORDER BY scaffold.day_num, prob.day_num






--*****************************************************************************************--------
--03 17 2020 currently admitted population---------------------------------------------------------
---------------------------------------------------------------------------------------------------
--*****************************************************************************************--------






--currently admitted population pop, check for arrival source type------------------------------
SELECT
	hsp.PAT_ENC_CSN_ID
	, hsp.admit_date
	, hsp.days_into_admission
	, hsp.PATIENT_SERVICE_GRP
	, hsp.PATIENT_SERVICE_NAME
	, CASE WHEN ob.PAT_ENC_CSN_ID IS NOT NULL THEN 'OB'
		WHEN neo.pat_enc_CSN_ID IS NOT NULL THEN 'Neonate'
		WHEN ed.PAT_ENC_CSN_ID IS NOT NULL THEN 'ED'
		WHEN extPop.PAT_ENC_CSN_ID IS NOT NULL THEN 'Direct Admit (External Transfer)'
		WHEN periop.PAT_ENC_CSN_ID IS NOT NULL THEN 'Surgical Admit'
		ELSE 'Other' END Admit_source
	, COALESCE(periop.Primary_Procedure, 'N/A') as Primary_Procedure
	, COALESCE(ob.OB_Status, neo.neonateStatus, ed.ED_to_ED_Transfer_Flag, extPop.REQUEST_TYPE, 'N/A') as sub_type
	, COALESCE(neo.department_name, ed.ACUITY_LEVEL, extPop.TRANSFER_TYPE, 'N/A') as severity_level
INTO #currentAdmitPop2
from #currentAdmitPop hsp --based on CLARITY..PAT_ENC_HSP, but nicely pre-filtered. Helps be consistent
LEFT JOIN #extTransferPop extPop
	ON extPop.PAT_ENC_CSN_ID = hsp.PAT_ENC_CSN_ID
	AND extpop.direct_admit_flag = 1 --only direct admits
LEFT JOIN #EDpop ed	ON ed.PAT_ENC_CSN_ID = hsp.PAT_ENC_CSN_ID
LEFT JOIN #surgicalPop periop	ON periop.PAT_ENC_CSN_ID = hsp.PAT_ENC_CSN_ID
LEFT JOIN #OBpop ob ON ob.PAT_ENC_CSN_ID = hsp.PAT_ENC_CSN_ID
LEFT JOIN #neonatePop neo on neo.pat_enc_CSN_ID = hsp.pat_enc_CSN_ID

--LOS Prob dist for curr admits---------------------------------------
SELECT
       tmp.PATIENT_SERVICE_GRP, tmp.PATIENT_SERVICE_NAME, scaffold.day_num
       , COUNT(*) denominator, SUM(CASE WHEN tmp.LOS > scaffold.day_num THEN 1 ELSE 0 END) numerator --use greater than to align with #scaffold. e.g. 1 day LOS will only show up on day 0, which is really the first day.
       , CAST(SUM(CASE WHEN tmp.LOS > scaffold.day_num THEN 1 ELSE 0 END) AS FLOAT) / CAST(COUNT(*) AS FLOAT) probability
INTO #currentAdmitsLOSprobDist
FROM #allEncounters tmp
JOIN #scaffold scaffold       ON 1 = 1
WHERE tmp.HOSP_DISCH_TIME IS NOT NULL --actual discharges
	AND tmp.HOSP_DISCH_TIME < @endDate --for testing purposes
GROUP BY tmp.PATIENT_SERVICE_GRP, tmp.PATIENT_SERVICE_NAME, scaffold.day_num
--ORDER BY tmp.PATIENT_SERVICE_GRP, tmp.PATIENT_SERVICE_NAME, scaffold.day_num
--curr pop Scaffolded---------------------------------------
SELECT
	temp.PAT_ENC_CSN_ID --, temp.HSP_ACCOUNT_ID, temp.PAT_ID
	, temp.admit_date
	, COALESCE(prob.day_num, scaffold2.day_num) day_num
	, COALESCE(prob.day_num - temp.days_into_admission, scaffold2.day_num) AS day_num_adjusted
	, dateadd(day, COALESCE(prob.day_num - temp.days_into_admission, scaffold2.day_num) -1
		, @endDate) as day_date
	, temp.days_into_admission
	, temp.PATIENT_SERVICE_GRP
	, temp.PATIENT_SERVICE_NAME
	--, COALESCE(prob.probability, 1) AS rawProb, COALESCE(condProb.probability, 1) AS condProbDenom
	, CASE WHEN scaffold2.day_num IS NOT NULL THEN 1
		WHEN condProb.probability > 0 then prob.probability / condProb.probability
		ELSE 1 END AS adjustedProb
	, temp.Admit_source
	, temp.Primary_Procedure
	, temp.sub_type
	, temp.severity_level
INTO #currentAdmitFinalScaffold
FROM #currentAdmitPop2 temp
LEFT JOIN #currentAdmitsLOSprobDist condProb --get current day of admission, to find Probability they'd be here this long, to adjust future probabilities
       ON temp.days_into_admission = condProb.day_num
       AND temp.PATIENT_SERVICE_NAME = condProb.PATIENT_SERVICE_NAME
LEFT JOIN #currentAdmitsLOSprobDist prob --get all future probabilities to build 'decay rate' for each patient
       ON temp.days_into_admission <= prob.day_num  --day_num 0-365, days_into_admit 0-999 (based on datediff from GETDATE-1)
       AND temp.PATIENT_SERVICE_NAME = prob.PATIENT_SERVICE_NAME
LEFT JOIN #scaffold scaffold2 ON temp.days_into_admission > 365 --for patients already here more than 365 days, bring in 2nd scaffold, as they don't join well for the main one
WHERE COALESCE(prob.day_num - temp.days_into_admission, scaffold2.day_num) <= @daysToPredictForward
	and COALESCE(prob.day_num - temp.days_into_admission, scaffold2.day_num) >= 0






--*****************************************************************************************-------
--Historical Midnight Censuses--------------------------------------------------------------------
--------------------------------------------------------------------------------------------------
--*****************************************************************************************-------





SELECT
	hsp.PAT_ENC_CSN_ID
	, dt.DAY_DATE as CENSUS_DATE
	, DATEDIFF(DAY, convert(date, hsp.HOSP_ADMSN_TIME, 101), dt.DAY_DATE) AS days_into_admission
	, hsp.PATIENT_SERVICE_GRP
	, hsp.PATIENT_SERVICE_NAME
	, CASE WHEN ob.PAT_ENC_CSN_ID IS NOT NULL THEN 'OB'
		WHEN neo.pat_enc_CSN_ID IS NOT NULL THEN 'Neonate'
		WHEN ed.PAT_ENC_CSN_ID IS NOT NULL THEN 'ED'
		WHEN extPop.PAT_ENC_CSN_ID IS NOT NULL THEN 'Direct Admit (External Transfer)'
		WHEN periop.PAT_ENC_CSN_ID IS NOT NULL THEN 'Surgical Admit'
		ELSE 'Other' END Admit_source
	, COALESCE(periop.Primary_Procedure, 'N/A') as Primary_Procedure
	, COALESCE(ob.OB_Status, neo.neonateStatus, ed.ED_to_ED_Transfer_Flag, extPop.REQUEST_TYPE, 'N/A') as sub_type
	, COALESCE(neo.department_name, ed.ACUITY_LEVEL, extPop.TRANSFER_TYPE, 'N/A') as severity_level
	, dep.DEPARTMENT_NAME
	, adt.EFFECTIVE_TIME census_actual_time
INTO #histCensus
from CLARITY_ADT adt
join CLARITY_REPORTING.dbo.DIM_DATE_V2 dt on dt.DAY_DATE = dateadd(dd, datediff(dd,0, adt.EFFECTIVE_TIME), 0)
join clarity_dep dep on dep.DEPARTMENT_ID = adt.DEPARTMENT_ID and dep.SERV_AREA_ID = 10
join #allEncounters hsp on hsp.PAT_ENC_CSN_ID = adt.PAT_ENC_CSN_ID
LEFT JOIN #extTransferPop extPop
	ON extPop.PAT_ENC_CSN_ID = hsp.PAT_ENC_CSN_ID
	--AND extpop.direct_admit_flag = 1 --only direct admits
LEFT JOIN #EDpop ed	ON ed.PAT_ENC_CSN_ID = hsp.PAT_ENC_CSN_ID
LEFT JOIN #surgicalPop periop	ON periop.PAT_ENC_CSN_ID = hsp.PAT_ENC_CSN_ID
LEFT JOIN #OBpop ob ON ob.PAT_ENC_CSN_ID = hsp.PAT_ENC_CSN_ID
LEFT JOIN #neonatePop neo on neo.pat_enc_CSN_ID = hsp.pat_enc_CSN_ID
where adt.EVENT_SUBTYPE_C <> 2
	and adt.EVENT_TYPE_C = 6
	AND dt.DAY_DATE >= DATEADD(year, 1, @historicalStartDate)
	and dt.DAY_DATE < dateadd(day, -1, @endDate) --move window an extra day back, as these patients are already being counted in currPop






--*****************************************************************************************-------
--FINAL UNION-------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------
--*****************************************************************************************-------






SELECT  --current population
	CAST(currPop.PAT_ENC_CSN_ID AS VARCHAR(50)) AS Uniq_ID
	, currPop.day_num_adjusted AS Days_Out
	, currPop.day_date as day_date
	, currPop.adjustedProb AS Est_Occupancy
	, currPop.Admit_source AS Pt_Type
	, -currPop.days_into_admission AS arrival_day
	, currPop.days_into_admission + currPop.day_num_adjusted as post_arr_day
	, 'Currently Admitted Patients' as prediction_status
	, currPop.Primary_Procedure as Primary_Procedure
	, currPop.sub_type as sub_type
	, currPop.severity_level as severity_level
FROM #currentAdmitFinalScaffold currPop

UNION ALL

SELECT  --predicted Direct Admit arrivals
	da.cat_ID AS Uniq_ID
	, da.day_num_actual AS Days_Out
	, da.day_date as day_date
	, da.predCensus AS Est_Occupancy
	, 'Direct Admit (External Transfer)' AS Pt_Type
	, da.arr_day AS arrival_day
	, da.post_arr_day
	, 'Predicted Admissions' as prediction_status
	, 'N/A' as Primary_Procedure
	, da.REQUEST_TYPE as sub_type
	, da.TRANSFER_TYPE as severity_level
FROM #directAdmitFinalScaffold da

UNION ALL

SELECT  --predicted ED arrivals
	ed.cat_ID AS Uniq_ID
	, ed.day_num_actual AS Days_Out
	, ed.day_date as day_date
	, ed.predCensus AS Est_Occupancy
	, 'ED' AS Pt_Type
	, ed.arr_day AS arrival_day
	, ed.post_arr_day
	, 'Predicted Admissions' as prediction_status
	, 'N/A' as Primary_Procedure
	, ed.ED_to_ED_Transfer_Flag as sub_type
	, ed.ACUITY_LEVEL AS severity_level
FROM #edFinalScaffold ed

UNION ALL

SELECT  --predicted "other" arrivals
	other.cat_ID AS Uniq_ID
	, other.day_num_actual AS Days_Out
	, other.day_date as day_date
	, other.predCensus AS Est_Occupancy
	, 'Other' AS Pt_Type
	, other.arr_day AS arrival_day
	, other.post_arr_day
	, 'Predicted Admissions' as prediction_status
	, 'N/A' as Primary_Procedure
	, 'N/A' as sub_type
	, 'N/A' as severity_level
FROM #otherFinalScaffold other

UNION ALL

SELECT  --expected OB arrivals
	ob.cat_ID AS Uniq_ID
	, ob.day_num_actual AS Days_Out
	, ob.day_date as day_date
	, ob.predCensus AS Est_Occupancy
	, 'OB' AS Pt_Type
	, ob.arr_day AS arrival_day
	, ob.post_arr_day
	, 'Expected Admissions' as prediction_status
	, 'N/A' as Primary_Procedure
	, ob.OB_Status as sub_type
	, 'N/A' as severity_level
FROM #obFinalScaffold ob

UNION ALL

SELECT  --predicted other OB arrivals
	ob2.cat_ID AS Uniq_ID
	, ob2.day_num_actual AS Days_Out
	, ob2.day_date as day_date
	, ob2.predCensus AS Est_Occupancy
	, 'OB' AS Pt_Type
	, ob2.arr_day AS arrival_day
	, ob2.post_arr_day
	, 'Predicted Admissions' as prediction_status
	, 'N/A' as Primary_Procedure
	, ob2.OB_Status as sub_type
	, 'N/A' as severity_level
FROM #obOtherFinalScaffold ob2

UNION ALL

SELECT  -- expected surgical admits
	surg.cat_ID AS Uniq_ID
	, surg.day_num_actual AS Days_Out
	, surg.day_date as day_date
	, surg.predCensus AS Est_Occupancy
	, 'Surgical Admit' AS Pt_Type
	, surg.arr_day AS arrival_day
	, surg.post_arr_day
	, 'Expected Admissions' as prediction_status
	, surg.Primary_Procedure as Primary_Procedure
	, surg.surgical_location as sub_type
	, 'N/A' as severity_level
FROM #surgicalFinalScaffold surg

UNION ALL

SELECT  -- expected neonate admits
	neo.cat_ID AS Uniq_ID
	, neo.day_num_actual AS Days_Out
	, neo.day_date as day_date
	, neo.predCensus AS Est_Occupancy
	, 'Neonate' AS Pt_Type
	, neo.arr_day AS arrival_day
	, neo.post_arr_day
	, 'Expected Admissions' as prediction_status
	, 'N/A' as Primary_Procedure
	, neo.neonateStatus as sub_type
	, neo.department_name as severity_level
FROM #neonateFinalScaffold neo

UNION ALL

SELECT  -- predicted non-UIHC neonate admits
	neo2.cat_ID AS Uniq_ID
	, neo2.day_num_actual AS Days_Out
	, neo2.day_date as day_date
	, neo2.predCensus AS Est_Occupancy
	, 'Neonate' AS Pt_Type
	, neo2.arr_day AS arrival_day
	, neo2.post_arr_day
	, 'Predicted Admissions' as prediction_status
	, 'N/A' as Primary_Procedure
	, neo2.neonateStatus as sub_type
	, neo2.department_name as severity_level
FROM #neonateOtherFinalScaffold neo2

UNION ALL

SELECT  --historical midnight census
	CAST(census.PAT_ENC_CSN_ID AS VARCHAR(50)) AS Uniq_ID
	, NULL AS Days_Out
	, census.CENSUS_DATE as day_date
	, 1.0 AS Est_Occupancy
	, census.Admit_source AS Pt_Type
	, NULL AS arrival_day
	, days_into_admission as post_arr_day
	, 'Historical Census' as prediction_status
	, census.Primary_Procedure as Primary_Procedure
	, census.sub_type as sub_type
	, census.severity_level as severity_level
FROM #histCensus census
