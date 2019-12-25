SELECT 
  dfn.file_name as "Table Path", 
  df.tablespace_name as "Tablespace",
  rtrim(to_char(df.totalspace/1024, 'FM90.9'), '.')||' | '||df.totalspace  as "Total GB/MB",
  totalusedspace as "Used MB",
  (df.totalspace - tu.totalusedspace) as "Free MB",
  ROUND(100 * ( (df.totalspace - tu.totalusedspace)/ df.totalspace)) as "% Free"
FROM
  (SELECT tablespace_name,
    ROUND(SUM(bytes)/(1024*1024)) TotalSpace
  FROM dba_data_files
  GROUP BY tablespace_name
  ) df,
  (SELECT ROUND(SUM(bytes)/(1024*1024)) totalusedspace,
    tablespace_name
  FROM dba_segments
  GROUP BY tablespace_name
  ) tu
  , dba_data_files dfn
WHERE df.tablespace_name = tu.tablespace_name
and df.tablespace_name = dfn.tablespace_name;
