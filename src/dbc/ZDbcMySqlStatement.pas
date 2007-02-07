{*********************************************************}
{                                                         }
{                 Zeos Database Objects                   }
{           MySQL Database Connectivity Classes           }
{                                                         }
{        Originally written by Sergey Seroukhov           }
{                                                         }
{*********************************************************}

{@********************************************************}
{    Copyright (c) 1999-2006 Zeos Development Group       }
{                                                         }
{ License Agreement:                                      }
{                                                         }
{ This library is distributed in the hope that it will be }
{ useful, but WITHOUT ANY WARRANTY; without even the      }
{ implied warranty of MERCHANTABILITY or FITNESS FOR      }
{ A PARTICULAR PURPOSE.  See the GNU Lesser General       }
{ Public License for more details.                        }
{                                                         }
{ The source code of the ZEOS Libraries and packages are  }
{ distributed under the Library GNU General Public        }
{ License (see the file COPYING / COPYING.ZEOS)           }
{ with the following  modification:                       }
{ As a special exception, the copyright holders of this   }
{ library give you permission to link this library with   }
{ independent modules to produce an executable,           }
{ regardless of the license terms of these independent    }
{ modules, and to copy and distribute the resulting       }
{ executable under terms of your choice, provided that    }
{ you also meet, for each linked independent module,      }
{ the terms and conditions of the license of that module. }
{ An independent module is a module which is not derived  }
{ from or based on this library. If you modify this       }
{ library, you may extend this exception to your version  }
{ of the library, but you are not obligated to do so.     }
{ If you do not wish to do so, delete this exception      }
{ statement from your version.                            }
{                                                         }
{                                                         }
{ The project web site is located on:                     }
{   http://zeos.firmos.at  (FORUM)                        }
{   http://zeosbugs.firmos.at (BUGTRACKER)                }
{   svn://zeos.firmos.at/zeos/trunk (SVN Repository)      }
{                                                         }
{   http://www.sourceforge.net/projects/zeoslib.          }
{   http://www.zeoslib.sourceforge.net                    }
{                                                         }
{                                                         }
{                                                         }
{                                 Zeos Development Group. }
{********************************************************@}

unit ZDbcMySqlStatement;

interface

{$I ZDbc.inc}

uses
  Classes, SysUtils, ZDbcIntfs, ZDbcStatement, ZPlainMySqlDriver, ZPlainMySqlConstants,
  ZCompatibility, ZDbcLogging, ZVariant;

type

  {** Represents a MYSQL specific connection interface. }
  IZMySQLStatement = interface (IZStatement)
    ['{A05DB91F-1E40-46C7-BF2E-25D74978AC83}']

    function IsUseResult: Boolean;
{$IFDEF MYSQL_USE_PREPARE}
    function IsPreparedStatement: Boolean;
    function GetStmtHandle: PZMySqlPrepStmt;
{$ENDIF}
  end;

{$IFDEF MYSQL_USE_PREPARE}
  {** Represents a MYSQL prepared Statement specific connection interface. }
  IZMySQLPreparedStatement = interface (IZMySQLStatement)
    ['{A05DB91F-1E40-46C7-BF2E-25D74978AC83}']
  end;
{$ENDIF}

  {** Implements Generic MySQL Statement. }
  TZMySQLStatement = class(TZAbstractStatement, IZMySQLStatement)
  private
    FHandle: PZMySQLConnect;
    FPlainDriver: IZMySQLPlainDriver;
    FUseResult: Boolean;

    function CreateResultSet(const SQL: string): IZResultSet;
{$IFDEF MYSQL_USE_PREPARE}
    function GetStmtHandle : PZMySqlPrepStmt;
{$ENDIF}
  public
    constructor Create(PlainDriver: IZMySQLPlainDriver;
      Connection: IZConnection; Info: TStrings; Handle: PZMySQLConnect);

    function ExecuteQuery(const SQL: string): IZResultSet; override;
    function ExecuteUpdate(const SQL: string): Integer; override;
    function Execute(const SQL: string): Boolean; override;

    function IsUseResult: Boolean;
{$IFDEF MYSQL_USE_PREPARE}
    function IsPreparedStatement: Boolean;
{$ENDIF}
  end;

  {** Implements Prepared SQL Statement. }
  TZMySQLEmulatedPreparedStatement = class(TZEmulatedPreparedStatement)
  private
    FHandle: PZMySQLConnect;
    FPlainDriver: IZMySQLPlainDriver;
  protected
    function CreateExecStatement: IZStatement; override;
    function GetEscapeString(const Value: string): string;
    function PrepareSQLParam(ParamIndex: Integer): string; override;
  public
    constructor Create(PlainDriver: IZMySQLPlainDriver;
      Connection: IZConnection; const SQL: string; Info: TStrings;
      Handle: PZMySQLConnect);
  end;

{$IFNDEF MYSQL_USE_PREPARE}
  TZMySQLPreparedStatement = class(TZMySQLEmulatedPreparedStatement)
  end;
{$ELSE}
  {** Implements Prepared SQL Statement. }
  TZMySQLPreparedStatement = class(TZAbstractPreparedStatement,IZMySQLPreparedStatement)
  private
    FPrepared: Boolean;
    FHandle: PZMySQLConnect;
    FStmtHandle: PZMySqlPrepStmt;
    FPlainDriver: IZMySQLPlainDriver;
    FUseResult: Boolean;

    FParamBindArray: Array of MYSQL_BIND2;
    FParamArray: Array of PDOBindRecord2;
    function CreateResultSet(const SQL: string): IZResultSet;

    procedure PrepareParameters;
    function getFieldType (testVariant: TZVariant): Byte;
  protected
    property Prepared: Boolean read FPrepared write FPrepared;
    function GetStmtHandle : PZMySqlPrepStmt;
  public
    property StmtHandle: PZMySqlPrepStmt read GetStmtHandle;
    constructor Create(PlainDriver: IZMysqlPlainDriver; Connection: IZConnection; const SQL: string; Info: TStrings);
    destructor Destroy; override;

    function ExecuteQuery(const SQL: string): IZResultSet; override;
    function ExecuteUpdate(const SQL: string): Integer; override;
    function Execute(const SQL: string): Boolean; override;

    function ExecuteQueryPrepared: IZResultSet; override;
    function ExecuteUpdatePrepared: Integer; override;
    function ExecutePrepared: Boolean; override;

    function IsUseResult: Boolean;
    function IsPreparedStatement: Boolean;
  end;
{$ENDIF MYSQL_USE_PREPARE}

implementation

uses
  ZDbcMySql, ZDbcMySqlUtils, ZDbcMySqlResultSet, ZMySqlToken, ZSysUtils,
  ZMessages, ZDbcCachedResultSet, ZDbcUtils{$IFNDEF VER130BELOW}, DateUtils{$ENDIF};

{ TZMySQLStatement }

{**
  Constructs this object and assignes the main properties.
  @param PlainDriver a native MySQL plain driver.
  @param Connection a database connection object.
  @param Handle a connection handle pointer.
  @param Info a statement parameters.
}
constructor TZMySQLStatement.Create(PlainDriver: IZMySQLPlainDriver;
  Connection: IZConnection; Info: TStrings; Handle: PZMySQLConnect);
var
  MySQLConnection: IZMySQLConnection;
begin
  inherited Create(Connection, Info);
  FHandle := Handle;
  FPlainDriver := PlainDriver;
  ResultSetType := rtScrollInsensitive;

  MySQLConnection := Connection as IZMySQLConnection;
  FUseResult := StrToBoolEx(DefineStatementParameter(Self, 'useresult', 'false'));
end;

{**
  Checks is use result should be used in result sets.
  @return <code>True</code> use result in result sets,
    <code>False</code> store result in result sets.
}
function TZMySQLStatement.IsUseResult: Boolean;
begin
  Result := FUseResult;
end;

{$IFDEF MYSQL_USE_PREPARE}
{**
  Checks if this is a prepared mysql statement.
  @return <code>False</code> This is not a prepared mysql statement.
}
function TZMySQLStatement.IsPreparedStatement: Boolean;
begin
  Result := False;
end;

function TZMySQLStatement.GetStmtHandle: PZMySqlPrepStmt;
begin
  Result := nil;
end;
{$ENDIF}

{**
  Creates a result set based on the current settings.
  @return a created result set object.
}
function TZMySQLStatement.CreateResultSet(const SQL: string): IZResultSet;
var
  CachedResolver: TZMySQLCachedResolver;
  NativeResultSet: TZMySQLResultSet;
  CachedResultSet: TZCachedResultSet;
begin
  NativeResultSet := TZMySQLResultSet.Create(FPlainDriver, Self, SQL, FHandle,
    FUseResult);
  NativeResultSet.SetConcurrency(rcReadOnly);
  if (GetResultSetConcurrency <> rcReadOnly) or (FUseResult
    and (GetResultSetType <> rtForwardOnly)) then
  begin
    CachedResolver := TZMySQLCachedResolver.Create(FPlainDriver, FHandle, Self,
      NativeResultSet.GetMetaData);
    CachedResultSet := TZCachedResultSet.Create(NativeResultSet, SQL,
      CachedResolver);
    CachedResultSet.SetConcurrency(GetResultSetConcurrency);
    Result := CachedResultSet;
  end else
    Result := NativeResultSet;
end;


{**
  Executes an SQL statement that returns a single <code>ResultSet</code> object.
  @param sql typically this is a static SQL <code>SELECT</code> statement
  @return a <code>ResultSet</code> object that contains the data produced by the
    given query; never <code>null</code>
}
function TZMySQLStatement.ExecuteQuery(const SQL: string): IZResultSet;
begin
  Result := nil;
  if FPlainDriver.ExecQuery(FHandle, PChar(SQL)) = 0 then
  begin
    DriverManager.LogMessage(lcExecute, FPlainDriver.GetProtocol, SQL);
{$IFDEF ENABLE_MYSQL_DEPRECATED}
    if FPlainDriver.GetClientVersion < 32200 then
      begin
        // ResultSetExists is only useable since mysql 3.22
        if FPlainDriver.GetStatus(FHandle) = MYSQL_STATUS_READY then
          raise EZSQLException.Create(SCanNotOpenResultSet);
      end
    else
{$ENDIF ENABLE_MYSQL_DEPRECATED}
    if not FPlainDriver.ResultSetExists(FHandle) then
      raise EZSQLException.Create(SCanNotOpenResultSet);
    Result := CreateResultSet(SQL);
  end else
    CheckMySQLError(FPlainDriver, FHandle, lcExecute, SQL);
end;

{**
  Executes an SQL <code>INSERT</code>, <code>UPDATE</code> or
  <code>DELETE</code> statement. In addition,
  SQL statements that return nothing, such as SQL DDL statements,
  can be executed.

  @param sql an SQL <code>INSERT</code>, <code>UPDATE</code> or
    <code>DELETE</code> statement or an SQL statement that returns nothing
  @return either the row count for <code>INSERT</code>, <code>UPDATE</code>
    or <code>DELETE</code> statements, or 0 for SQL statements that return nothing
}
function TZMySQLStatement.ExecuteUpdate(const SQL: string): Integer;
var
  QueryHandle: PZMySQLResult;
  HasResultset : Boolean;
begin
  Result := -1;
  if FPlainDriver.ExecQuery(FHandle, PChar(SQL)) = 0 then
  begin
    DriverManager.LogMessage(lcExecute, FPlainDriver.GetProtocol, SQL);
{$IFDEF ENABLE_MYSQL_DEPRECATED}
    if FPlainDriver.GetClientVersion < 32200 then
      HasResultSet := FPlainDriver.GetStatus(FHandle) <> MYSQL_STATUS_READY
    else
      HasResultSet := FPlainDriver.ResultSetExists(FHandle);
{$ELSE}
    HasResultSet := FPlainDriver.ResultSetExists(FHandle);
{$ENDIF ENABLE_MYSQL_DEPRECATED}
    { Process queries with result sets }
    if HasResultSet then
    begin
      QueryHandle := FPlainDriver.StoreResult(FHandle);
      if QueryHandle <> nil then
      begin
        Result := FPlainDriver.GetRowCount(QueryHandle);
        FPlainDriver.FreeResult(QueryHandle);
      end else
        Result := FPlainDriver.GetAffectedRows(FHandle);
    end
    { Process regular query }
    else Result := FPlainDriver.GetAffectedRows(FHandle);
  end else
    CheckMySQLError(FPlainDriver, FHandle, lcExecute, SQL);
  LastUpdateCount := Result;
end;

{**
  Executes an SQL statement that may return multiple results.
  Under some (uncommon) situations a single SQL statement may return
  multiple result sets and/or update counts.  Normally you can ignore
  this unless you are (1) executing a stored procedure that you know may
  return multiple results or (2) you are dynamically executing an
  unknown SQL string.  The  methods <code>execute</code>,
  <code>getMoreResults</code>, <code>getResultSet</code>,
  and <code>getUpdateCount</code> let you navigate through multiple results.

  The <code>execute</code> method executes an SQL statement and indicates the
  form of the first result.  You can then use the methods
  <code>getResultSet</code> or <code>getUpdateCount</code>
  to retrieve the result, and <code>getMoreResults</code> to
  move to any subsequent result(s).

  @param sql any SQL statement
  @return <code>true</code> if the next result is a <code>ResultSet</code> object;
  <code>false</code> if it is an update count or there are no more results
}
function TZMySQLStatement.Execute(const SQL: string): Boolean;
var
  HasResultset : Boolean;
begin
  Result := False;
  if FPlainDriver.ExecQuery(FHandle, PChar(SQL)) = 0 then
  begin
    DriverManager.LogMessage(lcExecute, FPlainDriver.GetProtocol, SQL);
{$IFDEF ENABLE_MYSQL_DEPRECATED}
    if FPlainDriver.GetClientVersion < 32200 then
      HasResultSet := FPlainDriver.GetStatus(FHandle) <> MYSQL_STATUS_READY
    else
      HasResultSet := FPlainDriver.ResultSetExists(FHandle);
{$ELSE}
    HasResultSet := FPlainDriver.ResultSetExists(FHandle);
{$ENDIF ENABLE_MYSQL_DEPRECATED}
    { Process queries with result sets }
    if HasResultSet then
    begin
      Result := True;
      LastResultSet := CreateResultSet(SQL);
    end
    { Processes regular query. }
    else
    begin
      Result := False;
      LastUpdateCount := FPlainDriver.GetAffectedRows(FHandle);
    end;
  end else
    CheckMySQLError(FPlainDriver, FHandle, lcExecute, SQL);
end;

{ TZMySQLEmulatedPreparedStatement }

{**
  Constructs this object and assignes the main properties.
  @param PlainDriver a native MySQL Plain driver.
  @param Connection a database connection object.
  @param Info a statement parameters.
  @param Handle a connection handle pointer.
}
constructor TZMySQLEmulatedPreparedStatement.Create(PlainDriver: IZMySQLPlainDriver;
  Connection: IZConnection; const SQL: string; Info: TStrings; Handle: PZMySQLConnect);
begin
  inherited Create(Connection, SQL, Info);
  FHandle := Handle;
  FPlainDriver := PlainDriver;
  ResultSetType := rtScrollInsensitive;
end;

{**
  Creates a temporary statement which executes queries.
  @param Info a statement parameters.
  @return a created statement object.
}
function TZMySQLEmulatedPreparedStatement.CreateExecStatement: IZStatement;
begin
  Result := TZMySQLStatement.Create(FPlainDriver, Connection, Info,FHandle);
end;

{**
  Converts an string into escape MySQL format.
  @param Value a regular string.
  @return a string in MySQL escape format.
}
function TZMySQLEmulatedPreparedStatement.GetEscapeString(const Value: string): string;
var
  BufferLen: Integer;
  Buffer: PChar;
begin
  BufferLen := Length(Value) * 2 + 1;
  GetMem(Buffer, BufferLen);
  BufferLen := FPlainDriver.GetEscapeString(Buffer, PChar(Value), Length(Value));
  Result := '''' + BufferToStr(Buffer, BufferLen) + '''';
  FreeMem(Buffer);
end;

{**
  Prepares an SQL parameter for the query.
  @param ParameterIndex the first parameter is 1, the second is 2, ...
  @return a string representation of the parameter.
}
function TZMySQLEmulatedPreparedStatement.PrepareSQLParam(ParamIndex: Integer): string;
var
  Value: TZVariant;
  TempBytes: TByteDynArray;
  TempBlob: IZBlob;

  AYear, AMonth, ADay, AHour, AMinute, ASecond, AMilliSecond: Word;
begin
  TempBytes := nil;
  if InParamCount <= ParamIndex then
    raise EZSQLException.Create(SInvalidInputParameterCount);

  Value := InParamValues[ParamIndex];
  if DefVarManager.IsNull(Value) then
    if (InParamDefaultValues[ParamIndex] <> '') and
      StrToBoolEx(DefineStatementParameter(Self, 'defaults', 'true')) then
      Result := InParamDefaultValues[ParamIndex]
    else
      Result := 'NULL'
  else begin
    case InParamTypes[ParamIndex] of
      stBoolean:
        if SoftVarManager.GetAsBoolean(Value) then Result := '''Y'''
        else Result := '''N''';
      stByte, stShort, stInteger, stLong, stBigDecimal, stFloat, stDouble:
        Result := SoftVarManager.GetAsString(Value);
      stString, stBytes:
        Result := GetEscapeString(SoftVarManager.GetAsString(Value));
      stDate:
      begin
        {$IFNDEF VER130BELOW}
        DecodeDateTime(SoftVarManager.GetAsDateTime(Value),
          AYear, AMonth, ADay, AHour, AMinute, ASecond, AMilliSecond);
        {$ELSE}
        DecodeDate(SoftVarManager.GetAsDateTime(Value),
          AYear, AMonth, ADay);
        DecodeTime(SoftVarManager.GetAsDateTime(Value),
          AHour, AMinute, ASecond, AMilliSecond);
        {$ENDIF}
        Result := '''' + Format('%0.4d-%0.2d-%0.2d',
          [AYear, AMonth, ADay]) + '''';
      end;
      stTime:
      begin
        {$IFNDEF VER130BELOW}
        DecodeDateTime(SoftVarManager.GetAsDateTime(Value),
          AYear, AMonth, ADay, AHour, AMinute, ASecond, AMilliSecond);
        {$ELSE}
        DecodeDate(SoftVarManager.GetAsDateTime(Value),
          AYear, AMonth, ADay);
        DecodeTime(SoftVarManager.GetAsDateTime(Value),
          AHour, AMinute, ASecond, AMilliSecond);
        {$ENDIF}
        Result := '''' + Format('%0.2d:%0.2d:%0.2d',
          [AHour, AMinute, ASecond]) + '''';
      end;
      stTimestamp:
      begin
        {$IFNDEF VER130BELOW}
        DecodeDateTime(SoftVarManager.GetAsDateTime(Value),
          AYear, AMonth, ADay, AHour, AMinute, ASecond, AMilliSecond);
        {$ELSE}
        DecodeDate(SoftVarManager.GetAsDateTime(Value),
          AYear, AMonth, ADay);
        DecodeTime(SoftVarManager.GetAsDateTime(Value),
          AHour, AMinute, ASecond, AMilliSecond);
        {$ENDIF}
        Result := '''' + Format('%0.4d-%0.2d-%0.2d %0.2d:%0.2d:%0.2d',
          [AYear, AMonth, ADay, AHour, AMinute, ASecond]) + '''';
      end;
      stAsciiStream, stUnicodeStream, stBinaryStream:
        begin
          TempBlob := DefVarManager.GetAsInterface(Value) as IZBlob;
          if not TempBlob.IsEmpty then
            Result := GetEscapeString(TempBlob.GetString)
          else Result := 'NULL';
        end;
    end;
  end;
end;

{$IFDEF MYSQL_USE_PREPARE}
{ TZMySQLPreparedStatement }

{**
  Constructs this object and assignes the main properties.
  @param PlainDriver a Oracle plain driver.
  @param Connection a database connection object.
  @param Info a statement parameters.
  @param Handle a connection handle pointer.
}
constructor TZMySQLPreparedStatement.Create(
  PlainDriver: IZMySQLPlainDriver; Connection: IZConnection;
  const SQL: string; Info: TStrings);
var
  MySQLConnection: IZMySQLConnection;
begin
  inherited Create(Connection, SQL, Info);
  MySQLConnection := Connection as IZMySQLConnection;
  FHandle := MysqlConnection.GetConnectionHandle;
  FPlainDriver := PlainDriver;
  ResultSetType := rtScrollInsensitive;

  MySQLConnection := Connection as IZMySQLConnection;
  FUseResult := StrToBoolEx(DefineStatementParameter(Self, 'useresult', 'false'));
  FPrepared := False;

  FStmtHandle := FPlainDriver.InitializePrepStmt(FHandle);
  if (FStmtHandle = nil) then
    begin
      CheckMySQLPrepStmtError(FPlainDriver, FStmtHandle, lcPrepStmt, SFailedtoInitPrepStmt);
      exit;
    end;
  if (FPlainDriver.PrepareStmt(FStmtHandle, PChar(SQL),length(SQL)) <> 0) then
    begin
      CheckMySQLPrepStmtError(FPlainDriver, FStmtHandle, lcPrepStmt, SFailedtoPrepareStmt);
      exit;
    end;
  FPrepared := true;
  DriverManager.LogMessage(lcPrepStmt, FPlainDriver.GetProtocol, SQL);
end;

{**
  Destroys this object and cleanups the memory.
}
destructor TZMySQLPreparedStatement.Destroy;
begin
  inherited Destroy;
end;

{**
  Checks is use result should be used in result sets.
  @return <code>True</code> use result in result sets,
    <code>False</code> store result in result sets.
}
function TZMySQLPreparedStatement.IsUseResult: Boolean;
begin
  Result := FUseResult;
end;

{**
  Checks if this is a prepared mysql statement.
  @return <code>True</code> This is a prepared mysql statement.
}
function TZMySQLPreparedStatement.IsPreparedStatement: Boolean;
begin
  Result := True;
end;

{**
  Creates a result set based on the current settings.
  @return a created result set object.
}
function TZMySQLPreparedStatement.CreateResultSet(const SQL: string): IZResultSet;
var
  CachedResolver: TZMySQLCachedResolver;
  NativeResultSet: TZMySQLPreparedResultSet;
  CachedResultSet: TZCachedResultSet;
begin
  NativeResultSet := TZMySQLPreparedResultSet.Create(FPlainDriver, Self, SQL, FHandle,
    FUseResult);
  NativeResultSet.SetConcurrency(rcReadOnly);
  if (GetResultSetConcurrency <> rcReadOnly) or (FUseResult
    and (GetResultSetType <> rtForwardOnly)) then
  begin
    CachedResolver := TZMySQLCachedResolver.Create(FPlainDriver, FHandle, (Self as IZMysqlStatement),
      NativeResultSet.GetMetaData);
    CachedResultSet := TZCachedResultSet.Create(NativeResultSet, SQL,
      CachedResolver);
    CachedResultSet.SetConcurrency(GetResultSetConcurrency);
    Result := CachedResultSet;
  end else
    Result := NativeResultSet;
end;

procedure TZMysqlPreparedStatement.PrepareParameters;
var
    field_size, field_size_twin: LongWord;
    field_type: Byte;
    caststring : AnsiString;
    PBuffer: Pointer;
  I,J : integer;
begin
  If InParamCount = 0 then exit;
    { Initialize Bind Array and Column Array }
  SetLength(FParamBindArray, InParamCount);
  SetLength(FParamArray, InParamCount);

  For I := 0 to InParamCount - 1 do
  begin
    field_type := GetFieldType(InParamValues[I]);
    field_size := getMySQLFieldSize(field_type,255);
    if (field_type = FIELD_TYPE_STRING) then
      begin
        castString := InParamValues[I].VString;
        field_size := length(castString);
//        field_size_twin := field_size + 1;
        field_size_twin := field_size;
      end
    else field_size_twin := field_size;

    SetLength(FParamArray[I].buffer, field_size_twin);
    PBuffer := @FParamArray[I].buffer[0];
    with FParamBindArray[I] do begin
        buffer_type   := field_type;
        buffer_length := System.Length(FParamArray[I].buffer);
        is_unsigned   := 0;
        buffer        := @FParamArray[I].buffer[0];
        length        := @FParamArray[I].length;
        FParamArray[I].length := buffer_length;
        is_null       := @FParamArray[I].is_null;
        if InParamValues[I].VType=vtNull then
         FParamArray[I].is_null := 1
        else
         FParamArray[I].is_null := 0;
            case field_type of
              FIELD_TYPE_FLOAT:    Single(PBuffer^)     := InParamValues[I].VFloat;
              FIELD_TYPE_STRING:
                begin
                  CastString := InParamValues[I].VString;
                  for J := 1 to system.length(CastString) do
                    begin
                      PChar(PBuffer)^ := CastString[J];
                      inc(PChar(PBuffer));
                    end;
                  PChar(PBuffer)^ := chr(0);
                end;
              FIELD_TYPE_LONGLONG: Int64(PBuffer^) := InParamValues[I].VInteger;
            end;
     end;
  end;

     if (FPlainDriver.BindParameters(FStmtHandle, @FParamBindArray[0]) <> 0) then
        begin
          checkMySQLPrepStmtError (FPlainDriver, FStmtHandle, lcPrepStmt, SBindingFailure);
          exit;
        end;

end;

function TZMysqlPreparedStatement.getFieldType (testVariant: TZVariant): Byte;
begin
    case testVariant.vType of
        vtNull:      Result := FIELD_TYPE_TINY;
        vtBoolean:   Result := FIELD_TYPE_TINY;
        vtInteger:   Result := FIELD_TYPE_LONGLONG;
        vtFloat:    Result := FIELD_TYPE_FLOAT;
        vtString:    Result := FIELD_TYPE_STRING;
     else
        raise EZSQLException.Create(SUnsupportedDataType);
     end;
end;

{**
  Executes an SQL statement that returns a single <code>ResultSet</code> object.
  @param sql typically this is a static SQL <code>SELECT</code> statement
  @return a <code>ResultSet</code> object that contains the data produced by the
    given query; never <code>null</code>
}
function TZMySQLPreparedStatement.ExecuteQuery(const SQL: string): IZResultSet;
begin
  Self.SQL := SQL;
  Result := ExecuteQueryPrepared;
end;

{**
  Executes an SQL <code>INSERT</code>, <code>UPDATE</code> or
  <code>DELETE</code> statement. In addition,
  SQL statements that return nothing, such as SQL DDL statements,
  can be executed.

  @param sql an SQL <code>INSERT</code>, <code>UPDATE</code> or
    <code>DELETE</code> statement or an SQL statement that returns nothing
  @return either the row count for <code>INSERT</code>, <code>UPDATE</code>
    or <code>DELETE</code> statements, or 0 for SQL statements that return nothing
}
function TZMySQLPreparedStatement.ExecuteUpdate(const SQL: string): Integer;
begin
  Self.SQL := SQL;
  Result := ExecuteUpdatePrepared;
end;

{**
  Executes an SQL statement that may return multiple results.
  Under some (uncommon) situations a single SQL statement may return
  multiple result sets and/or update counts.  Normally you can ignore
  this unless you are (1) executing a stored procedure that you know may
  return multiple results or (2) you are dynamically executing an
  unknown SQL string.  The  methods <code>execute</code>,
  <code>getMoreResults</code>, <code>getResultSet</code>,
  and <code>getUpdateCount</code> let you navigate through multiple results.

  The <code>execute</code> method executes an SQL statement and indicates the
  form of the first result.  You can then use the methods
  <code>getResultSet</code> or <code>getUpdateCount</code>
  to retrieve the result, and <code>getMoreResults</code> to
  move to any subsequent result(s).

  @param sql any SQL statement
  @return <code>true</code> if the next result is a <code>ResultSet</code> object;
  <code>false</code> if it is an update count or there are no more results
}
function TZMySQLPreparedStatement.Execute(const SQL: string): Boolean;
begin
  Self.SQL := SQL;
  Result := ExecutePrepared;
end;

{**
  Executes the SQL query in this <code>PreparedStatement</code> object
  and returns the result set generated by the query.

  @return a <code>ResultSet</code> object that contains the data produced by the
    query; never <code>null</code>
}
function TZMySQLPreparedStatement.ExecuteQueryPrepared: IZResultSet;
begin
  Result := nil;
  PrepareParameters;
  if (self.FPlainDriver.ExecuteStmt(FStmtHandle) <> 0) then
     begin
        checkMySQLPrepStmtError(FPlainDriver,FStmtHandle, lcExecPrepStmt, SPreparedStmtExecFailure);
        exit;
     End;
  DriverManager.LogMessage(lcExecPrepStmt, FPlainDriver.GetProtocol, SQL);

  if FPlainDriver.GetPreparedFieldCount(FStmtHandle) = 0 then
      raise EZSQLException.Create(SCanNotOpenResultSet);
  Result := CreateResultSet(SQL);
end;

{**
  Executes the SQL INSERT, UPDATE or DELETE statement
  in this <code>PreparedStatement</code> object.
  In addition,
  SQL statements that return nothing, such as SQL DDL statements,
  can be executed.

  @return either the row count for INSERT, UPDATE or DELETE statements;
  or 0 for SQL statements that return nothing
}
function TZMySQLPreparedStatement.ExecuteUpdatePrepared: Integer;
var
  QueryHandle: PZMySQLResult;
  HasResultset : Boolean;
begin
  Result := -1;
  PrepareParameters;
  if (self.FPlainDriver.ExecuteStmt(FStmtHandle) <> 0) then
     begin
        checkMySQLPrepStmtError(FPlainDriver,FStmtHandle, lcExecPrepStmt, SPreparedStmtExecFailure);
        exit;
     End;
  DriverManager.LogMessage(lcExecPrepStmt, FPlainDriver.GetProtocol, SQL);
    { Process queries with result sets }
  if FPlainDriver.GetPreparedFieldCount(FStmtHandle) > 0 then
    begin
      FPlainDriver.StorePreparedResult(FStmtHandle);
      Result := FPlainDriver.GetPreparedAffectedRows(FStmtHandle);
    end
    { Process regular query }
  else
    Result := FPlainDriver.GetPreparedAffectedRows(FStmtHandle);
 LastUpdateCount := Result;
end;

{**
  Executes any kind of SQL statement.
  Some prepared statements return multiple results; the <code>execute</code>
  method handles these complex statements as well as the simpler
  form of statements handled by the methods <code>executeQuery</code>
  and <code>executeUpdate</code>.
  @see Statement#execute
}
function TZMySQLPreparedStatement.ExecutePrepared: Boolean;
var
  HasResultset : Boolean;
begin
  Result := False;
  PrepareParameters;
  if (FPlainDriver.ExecuteStmt(FStmtHandle) <> 0) then
     begin
        checkMySQLPrepStmtError(FPlainDriver,FStmtHandle, lcExecPrepStmt, SPreparedStmtExecFailure);
        exit;
     End;
  DriverManager.LogMessage(lcExecPrepStmt, FPlainDriver.GetProtocol, SQL);

  if FPlainDriver.GetPreparedFieldCount(FStmtHandle) > 0 then
    begin
      Result := True;
      LastResultSet := CreateResultSet(SQL);
    end
    { Processes regular query. }
  else
    begin
      Result := False;
      LastUpdateCount := FPlainDriver.GetPreparedAffectedRows(FStmtHandle);
    end;
end;

function TZMySQLPreparedStatement.GetStmtHandle: PZMySqlPrepStmt;
begin
  Result := FStmtHandle;
end;
{$ENDIF MYSQL_USE_PREPARE}

end.
