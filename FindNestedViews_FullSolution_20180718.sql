/*******************************************************************************************************************
Running this script as written will create duplicated views

Note: AdventureWorks2014 does not contain any nested views out-of-the-box.
Consequently, I have created several for testing for both AdventureWorks2014 and AdventureWorksDW2016
*******************************************************************************************************************/
use AdventureWorks2014;
go

if object_id ('[AdventureWorks2014].[HumanResources].[DuplicateEmployeeView]') is not null
	drop view [HumanResources].[DuplicateEmployeeView];
go

create view [HumanResources].[DuplicateEmployeeView] as 
(
	select *
	from HumanResources.vEmployee
);
go

if object_id ('[AdventureWorks2014].[HumanResources].[DuplicateEmployeeView2]') is not null
	drop view [HumanResources].[DuplicateEmployeeView2];
go

create view [HumanResources].[DuplicateEmployeeView2] as 
(
	select a.BusinessEntityID,b.City
	from HumanResources.DuplicateEmployeeView as a
		inner join HumanResources.vEmployee as b
		on a.BusinessEntityID = b.BusinessEntityID
);
go

if object_id ('[AdventureWorks2014].[HumanResources].[DuplicateEmployeeView3]') is not null
	drop view [HumanResources].[DuplicateEmployeeView3];
go

create view [HumanResources].[DuplicateEmployeeView3] as 
(
	select *
	from HumanResources.DuplicateEmployeeView
);
go


if object_id ('[AdventureWorks2014].[Sales].[DuplicateSalesView]') is not null
	drop view [Sales].[DuplicateSalesView];
go

create view [Sales].[DuplicateSalesView] as 
(
	select *
	from Sales.vSalesPerson
);
go

if object_id ('[AdventureWorks2014].[Sales].[DuplicateSalesView2]') is not null
	drop view [Sales].[DuplicateSalesView2];
go

create view [Sales].[DuplicateSalesView2] as 
(
	select a.BusinessEntityID,
		b.FirstName,
		b.LastName,
		b.JobTitle,
		c.CountryRegionName,
		dh.StartDate,
		dh.EndDate
	from [Sales].[DuplicateSalesView] as [a]
		inner join [Sales].[vSalesPerson] as [b]
		on [a].[BusinessEntityID] = [b].[BusinessEntityID]
			inner join HumanResources.vEmployee as c
			on c.BusinessEntityID = a.BusinessEntityID
				inner join HumanResources.vEmployeeDepartmentHistory as dh
				on dh.BusinessEntityID = a.BusinessEntityID
);
go

if object_id ('[AdventureWorks2014].[Sales].[DuplicateSalesView3]') is not null
	drop view [Sales].[DuplicateSalesView3];
go

create view [Sales].[DuplicateSalesView3] as 
(
	select *
	from Sales.[DuplicateSalesView]
);
go

/*******************************************************************************************************************
Create the stored procedure to count object references dynamically for each database and view specified for 
input parameters.
*******************************************************************************************************************/

use [master];
go

if object_id ('[master].[dbo].[CountObjectReferences_v2]') is not null
	drop procedure [dbo].[CountObjectReferences_v2];
go

create procedure [dbo].[CountObjectReferences_v2] (
    @DatabaseName as varchar(200),
    @QualifiedView as varchar(255),
    @RefCount as int output
) as
/*******************************************************************************************************************
Author: Alex Fleming
Create Date: 11-29-2017
Specify the database and qualified view input parameters and run it to return the number of references.
Examples of valid parameters: 'HumanResources.DuplicateEmployeeView3' or '[HumanResources].[DuplicateEmployeeView3]'
*******************************************************************************************************************/
set nocount on;
begin
declare @DynamicSQL varchar(max);

select @DynamicSQL = 'use ' + @DatabaseName + ';';
select @DynamicSQL = @DynamicSQL + 
    ' select count(*)
    from sys.dm_sql_referenced_entities(' + '''' + @QualifiedView + '''' + ',''object'') as RefEnt
	   inner join sys.all_views as AllViews
	   on RefEnt.referenced_id = AllViews.object_id
    where RefEnt.referenced_class = 1
    and RefEnt.referenced_minor_name is null;';

print @DynamicSQL;
exec (@DynamicSQL);

end;
go
/*******************************************************************************************************************
----------------------------------------------------TESTS----------------------------------------------------
use [master];
go
declare @RefCount int;
exec dbo.CountObjectReferences_v2 
    @DatabaseName = 'AdventureWorks2014',
    @QualifiedView = 'HumanResources.DuplicateEmployeeView3',
    @RefCount = @RefCount output;
*******************************************************************************************************************/

/*******************************************************************************************************************
Create the stored procedure to find all of the views that reference other views.
*******************************************************************************************************************/
use [master];
go

if object_id ('[master].[dbo].[FindNestedViews_v4]') is not null
	drop procedure [dbo].[FindNestedViews_v4];
go

create procedure [dbo].[FindNestedViews_v4] (@DBName as varchar(200), @ViewRefCount as int output) as
/*******************************************************************************************************************
Author: Alex Fleming
Create Date: 11-29-2017
This stored procedure finds all of the views in the specified database, stores them in a temp table, then passes them 
as parameters into the [dbo].[CountObjectReferences_v2] stored procedure and stores the results in a new table.
*******************************************************************************************************************/
set nocount on;

begin

    if object_id ('[tempdb]..[##SchemaViewTemp]') is not null
	   drop table ##SchemaViewTemp;

    create table ##SchemaViewTemp
    (  
	   SVID int identity(1,1) NOT NULL primary key,
	   SchemaViewString varchar(2000) NULL,
	   RefCount int null
    );  

    declare @DynamicSQL varchar(max);
    select @DynamicSQL = 'use ' + @DBName + ';';
    select @DynamicSQL = @DynamicSQL + 
	   ' insert into ##SchemaViewTemp (SchemaViewString)
	   select s.name + ''' + '.' + ''' + v.name as ''SchemaViewString''
	   from sys.all_views as v
		  inner join sys.schemas as s
		  on v.schema_id = s.schema_id
	   where v.object_id > 0
	   order by SchemaViewString;';
    print @DynamicSQL;
    exec (@DynamicSQL);

    if object_id ('[tempdb]..[##ViewReferences]') is not null
	   drop table ##ViewReferences;

    create table ##ViewReferences
    (  
	   RefID int identity(1,1) not null primary key,
	   RefCount int null
    );  

    declare @UpdateStmt varchar(500);
    declare @cnt as int = 0;
    declare @ViewString as nvarchar(255);
    declare NestedViewReader cursor for
	   select SchemaViewString
	   from ##SchemaViewTemp;
    
    open NestedViewReader;
		fetch next from NestedViewReader
		into @ViewString
		while @@FETCH_STATUS = 0
			begin
				insert into ##ViewReferences (RefCount)
				exec @ViewRefCount = dbo.CountObjectReferences_v2
				@QualifiedView = @ViewString,
				@DatabaseName = @DBName,
				@RefCount = @ViewRefCount output;

				select @UpdateStmt = 'use ' + @DBName + ';'
				select @UpdateStmt = @UpdateStmt +
					' update ##SchemaViewTemp 
					set RefCount = ' + cast((select RefCount from ##ViewReferences where RefID = @cnt + 1) as varchar(3)) +
					' where SVID = 1 + ' + cast(@cnt as varchar(2)) + ';';

				print @UpdateStmt;--for troubleshooting

				exec (@UpdateStmt);

				set @cnt = @cnt + 1;

				fetch next from NestedViewReader
				into @ViewString
			end;
    close NestedViewReader;
    deallocate NestedViewReader;

    drop table ##ViewReferences;

    select *
    from ##SchemaViewTemp 
    where RefCount > 0
    order by RefCount desc;

end;
go
/***********************************************************************************************************
----------------------------------------------------TESTS----------------------------------------------------
use [master];
go
-------First Database: AdventureWorks2014-------
declare @DBName as varchar(200) = 'AdventureWorks2014';
declare @ViewRefs int;
exec dbo.FindNestedViews_v4 @DBName = @DBName, @ViewRefCount = @ViewRefs output;
go
-------Repeat for additional databases-------
declare @DBName as varchar(200) = '<dbname>';
declare @ViewRefs int;
exec dbo.FindNestedViews_v4 @DBName = @DBName, @ViewRefCount = @ViewRefs output;
go
***********************************************************************************************************/

/***********************************************************************************************************
--UNCOMMENT AND RUN THIS SECTION FOR CLEAN UP:

use AdventureWorks2014;
go

drop view [HumanResources].[DuplicateEmployeeView];
go

drop view [HumanResources].[DuplicateEmployeeView2];
go

drop view [HumanResources].[DuplicateEmployeeView3];
go

drop view [Sales].[DuplicateSalesView];
go

drop view [Sales].[DuplicateSalesView2];
go

drop view [Sales].[DuplicateSalesView3];
go

use master;
go

drop procedure [dbo].[FindNestedViews_v4];
go

drop procedure [dbo].[CountObjectReferences_v2];
go
***********************************************************************************************************/