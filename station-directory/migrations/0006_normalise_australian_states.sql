UPDATE stations SET state = CASE
  WHEN instr(state, ',') > 0 THEN 'Unknown'
  WHEN upper(trim(state)) GLOB '*NSW*' OR lower(state) IN ('sydney','new south wales') THEN 'New South Wales'
  WHEN upper(trim(state)) GLOB '*VIC*' OR lower(state) IN ('melbourne','gippsland','victoria') THEN 'Victoria'
  WHEN upper(trim(state)) GLOB '*QLD*' OR lower(state) LIKE '%queensland%' OR lower(state)='brisbane' THEN 'Queensland'
  WHEN upper(trim(state)) GLOB '*TAS*' OR lower(state)='tasmania' THEN 'Tasmania'
  WHEN upper(trim(state)) GLOB '* ACT*' OR upper(trim(state))='ACT' OR lower(state)='australian capital territory' THEN 'Australian Capital Territory'
  WHEN upper(trim(state)) GLOB '* NT*' OR upper(trim(state))='NT' OR lower(state)='northern territory' THEN 'Northern Territory'
  WHEN upper(trim(state)) GLOB '* SA*' OR upper(trim(state))='SA' OR lower(state)='south australia' THEN 'South Australia'
  WHEN upper(trim(state)) GLOB '* WA*' OR upper(trim(state))='WA' OR lower(state)='western australia' THEN 'Western Australia'
  ELSE 'Unknown'
END;
UPDATE catalogue_meta SET revision=revision+1,updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id=1;
