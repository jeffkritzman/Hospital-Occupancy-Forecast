# Hospital-Occupancy-Forecast
Forecasting model for inpatient hospital arrivals, departures, and census

Based on Epic / Clarity data model.

Uses a combination of Time Series decomposition (weekly/holiday seasonality) and empirical probability modeling (adapted from OR literature)

Look at patients in terms of their 'arrival stream,' i.e. how did they come to the hospital? Was it a delivery, was it a planned surgery, was it the emergency room?

First, look at historical arrival data. Do a rolling average by day of week (combine weekends and observed holidays into one pseuo-day-of-week) for each arrival stream. 
For Surgeries, we have a surgery schedule, so use this. For OB / Deliveries, we have expected due dates for patients already in the system, so use this. For OB, you need an "Other" category to catch people who didn't get prenatal care here. For Surgical, you need a 'fudge factor' to account for cancellations and late scheduled cases (this is accomplished in my product in Tableau not SQL, though it could be done in SQL).

Next, look at historical patient stays by patient type (type is defined differently for different arrival streams). Create a proability matrix for each patient type (j) showing the probability that they will still be admitted on the nth day after admission, notated as P(j, n). 

Apply this to both currently admitted patients and to the arrival stream forecasts in order to build up a full occupancy model. 

For currently admitted patients, use conditional probability. I.e. a patient of type j who has already been admitted for m days has a probability of still being admitted on day n (n > m) of P(j, n | m) = P(j, n) / P(j, m). *

\* For stats nerds... If A is 'being admitted on day n' and B is 'being admitted on day m', then P(A & B) = P(A) for n > m, as you can't be admitted for n days and not also be admitted for m days. This is how we can simplify conditional probability as we did above.

Now, add them all up! This allows for an operational decision support tool, where leadership can switch different patient types / arrival streams on and off and see the impact on occupancy.
