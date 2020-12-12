--
-- Copyright (c) Oracle Corporation 1988, 1999.  All Rights Reserved.
--
--  NAME
--    demobld.sql
--
-- DESCRIPTION
--   This script creates the SQL*Plus demonstration tables in the
--   current schema.  It should be STARTed by each user wishing to
--   access the tables.  To remove the tables use the demodrop.sql
--   script.
--
--  USAGE
--       SQL> START demobld.sql
--
--

set termout on
PROMPT Building demonstration tables.  Please wait.
set termout off

drop table emp;
drop table dept;
drop table bonus;
drop table salgrade;
drop table dummy;

create table emp
       (empno number(4) not null,
        ename varchar2(10),
        job varchar2(9),
        mgr number(4),
        hiredate date,
        sal number(7, 2),
        comm number(7, 2),
        deptno number(2));

insert into emp values (7369, 'SMITH',  'CLERK',     7902, to_date('17-12-1980', 'DD-MM-YYYY'),  800, null, 20);
insert into emp values (7499, 'ALLEN',  'SALESMAN',  7698, to_date('20-02-1981', 'DD-MM-YYYY'), 1600,  300, 30);
insert into emp values (7521, 'WARD',   'SALESMAN',  7698, to_date('22-02-1981', 'DD-MM-YYYY'), 1250,  500, 30);
insert into emp values (7566, 'JONES',  'MANAGER',   7839, to_date('2-04-1981', 'DD-MM-YYYY'),  2975, null, 20);
insert into emp values (7654, 'MARTIN', 'SALESMAN',  7698, to_date('28-09-1981', 'DD-MM-YYYY'), 1250, 1400, 30);
insert into emp values (7698, 'BLAKE',  'MANAGER',   7839, to_date('1-05-1981', 'DD-MM-YYYY'),  2850, null, 30);
insert into emp values (7782, 'CLARK',  'MANAGER',   7839, to_date('9-06-1981', 'DD-MM-YYYY'),  2450, null, 10);
insert into emp values (7788, 'SCOTT',  'ANALYST',   7566, to_date('09-12-1982', 'DD-MM-YYYY'), 3000, null, 20);
insert into emp values (7839, 'KING',   'PRESIDENT', null, to_date('17-11-1981', 'DD-MM-YYYY'), 5000, null, 10);
insert into emp values (7844, 'TURNER', 'SALESMAN',  7698, to_date('8-09-1981', 'DD-MM-YYYY'),  1500,    0, 30);
insert into emp values (7876, 'ADAMS',  'CLERK',     7788, to_date('12-01-1983', 'DD-MM-YYYY'), 1100, null, 20);
insert into emp values (7900, 'JAMES',  'CLERK',     7698, to_date('3-12-1981', 'DD-MM-YYYY'),   950, null, 30);
insert into emp values (7902, 'FORD',   'ANALYST',   7566, to_date('3-12-1981', 'DD-MM-YYYY'),  3000, null, 20);
insert into emp values (7934, 'MILLER', 'CLERK',     7782, to_date('23-01-1982', 'DD-MM-YYYY'), 1300, null, 10);

create table dept (
     deptno number(2)
   , dname varchar2(14)
   , loc varchar2(13) 
);

insert into dept values (10, 'ACCOUNTING', 'NEW YORK');
insert into dept values (20, 'RESEARCH',   'DALLAS');
insert into dept values (30, 'SALES',      'CHICAGO');
insert into dept values (40, 'OPERATIONS', 'BOSTON');

create table bonus (
     ename varchar2(10)
   , job   varchar2(9)
   , sal   number
   , comm  number
);

create table salgrade (
     grade number
   , losal number
   , hisal number
);

insert into salgrade values (1,  700, 1200);
insert into salgrade values (2, 1201, 1400);
insert into salgrade values (3, 1401, 2000);
insert into salgrade values (4, 2001, 3000);
insert into salgrade values (5, 3001, 9999);

--create table dummy
--        (dummy number);

--insert into dummy values (0);

commit;

set termout on
PROMPT Demonstration table build is complete.

exit
