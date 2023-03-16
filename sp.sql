SET QUOTED_IDENTIFIER ON
SET ANSI_NULLS ON
GO

CREATE OR ALTER PROC p_Get_Return_Value
(@objectId INT)
AS
BEGIN

    EXEC p_Print
    PRINT 'p_Get_Return_Value ' + CAST(@objectId AS VARCHAR)
	PRINT 'process end'
    RETURN @objectId
END
GO


CREATE OR ALTER PROC p_Print
AS
BEGIN
    PRINT 'p_Print'
END