-----------------------------------------------------------------------------
--  DDL for Type F_GENERATOR_CRUD_TYPE and F_GENERATOR_CRUD_TABLE
-----------------------------------------------------------------------------
  create or replace type f_generator_crud_table as table of f_generator_crud_type; 
/
  create or replace type f_generator_crud_type as object( plsql_type varchar2(200),plsql_code varchar2(4000)); 
/



--------------------------------------------------------
--  DDL for Function F_GENERATOR_CRUD
--------------------------------------------------------

create or replace function f_generator_crud(
     p_table in varchar2
          ) return f_generator_crud_table
          pipelined
          authid current_user
     as
          vwt        f_generator_crud_table;
          pragma     autonomous_transaction;
begin

     select f_generator_crud_type (
          'body insert', 'procedure '||lower(p_table)||'_insert ('
          || listagg(lower('p_'||column_name)||' in ' ||lower(data_type), ', ') within group (order by column_id) 
          || ', p_person in varchar2);' 
          ) bulk collect into vwt
       from all_tab_cols
      where table_name = upper(p_table)
        and column_id > 1
        and owner = (select sys_context('USERENV','CURRENT_SCHEMA') from dual)
     union all
     select f_generator_crud_type (
          'body update', 'procedure '||lower(p_table)||'_update ('
          || listagg(lower('p_'||column_name)||' in ' ||lower(data_type), ', ') within group (order by column_id) 
          || ', p_person in varchar2);' 
          )
       from all_tab_cols
      where table_name = upper(p_table)
        and owner = (select sys_context('USERENV','CURRENT_SCHEMA') from dual)
     union all
     select f_generator_crud_type (
          'body delete', 'procedure '||lower(p_table)||'_delete ('
          || listagg(lower('p_'||column_name)||' in ' ||lower(data_type), ', ') within group (order by column_id) 
          || ', p_person in varchar2);' 
          )
       from all_tab_cols
      where table_name = upper(p_table)
        and column_id = 1
        and owner = (select sys_context('USERENV','CURRENT_SCHEMA') from dual)
     ;

     for i in 1..vwt.count loop
          pipe row ( f_generator_crud_type(vwt( i ).plsql_type,vwt( i ).plsql_code) );
     end loop;
     
end f_generator_crud;
/
