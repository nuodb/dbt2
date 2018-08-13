#include <string.h>
#include <stdio.h>
#include "nuodb_capi.h"
#include "NuoDB.h"

template<typename value_type>
value_type * cast(uintptr_t handle)
{
    return reinterpret_cast<value_type*>(handle);
}

template<typename value_type>
uintptr_t cast(value_type * value)
{
    return reinterpret_cast<uintptr_t>(value);
}

NUODB_CFUNC
void nuodb_set_error(nuodb_connection_t * connection, nuodb_error_code code, char const * error_text)
{
    connection->error = code;
    if (connection->error_message)
    {
        free((void*)connection->error_message);
    }
    connection->error_message = strdup(error_text);
}

NUODB_CFUNC
int nuodb_open(
    nuodb_connection_t * connection)
{
    if (!connection)
    {
        return NUODB_ILLEGAL_ARGUMENT;
    }

    try
    {
        connection->connection_handle = cast<NuoDB::Connection>(NuoDB::Connection::create());
        nuodb_set_error(connection, NUODB_ZERO_ERROR, "SUCCESS");
    }
    catch (NuoDB::SQLException & e)
    {
        nuodb_set_error(connection, NUODB_CONNECTION_ERROR, e.getText());
    }

    return connection->error;
}

NUODB_CFUNC
int nuodb_connect(
    nuodb_connection_t * connection,
    char const * database,
    char const * username,
    char const * password,
    char const * tmzone,
    char const * schema)
{
    if (!connection)
    {
        return NUODB_ILLEGAL_ARGUMENT;
    }
    if (!database)
    {
        nuodb_set_error(connection, NUODB_ILLEGAL_ARGUMENT, "Failed to specify database name.");
        return connection->error;
    }
    if (!username)
    {
        nuodb_set_error(connection, NUODB_ILLEGAL_ARGUMENT, "Failed to specify username.");
        return connection->error;
    }
    if (!password)
    {
        nuodb_set_error(connection, NUODB_ILLEGAL_ARGUMENT, "Failed to specify password.");
        return connection->error;
    }
    if (!schema)
    {
        nuodb_set_error(connection, NUODB_ILLEGAL_ARGUMENT, "Failed to specify schema name.");
        return connection->error;
    }

    try
    {
        NuoDB::Connection * nuodb_conn = cast<NuoDB::Connection>(connection->connection_handle);
        NuoDB::Properties * props = nuodb_conn->allocProperties();
        props->putValue("user", username);
        props->putValue("password", password);
        props->putValue("schema", schema);
        props->putValue("isolation", "read_committed");
        if (tmzone)
        {
            props->putValue("TimeZone", tmzone);
        }
        nuodb_conn->openDatabase(database, props);
        nuodb_conn->setAutoCommit(false);

        connection->statement_handle = cast<NuoDB::Statement>(nuodb_conn->createStatement());

        nuodb_set_error(connection, NUODB_ZERO_ERROR, "SUCCESS");
    }
    catch (NuoDB::SQLException & e)
    {
        nuodb_set_error(connection, NUODB_CONNECTION_ERROR, e.getText());
    }


    return connection->error;
}

NUODB_CFUNC
int nuodb_close(
    nuodb_connection_t * connection)
{
    if (!connection)
    {
        return NUODB_ILLEGAL_ARGUMENT;
    }

    try
    {
        NuoDB::Connection * nuodb_conn = cast<NuoDB::Connection>(connection->connection_handle);
        nuodb_conn->close();
        connection->connection_handle = 0;
        nuodb_set_error(connection, NUODB_ZERO_ERROR, "SUCCESS");
    }
    catch (NuoDB::SQLException & e)
    {
        nuodb_set_error(connection, NUODB_CONNECTION_ERROR, e.getText());
    }

    return connection->error;
}

NUODB_CFUNC
int nuodb_commit(
    nuodb_connection_t * connection)
{
    if (!connection)
    {
        return NUODB_ILLEGAL_ARGUMENT;
    }

    try
    {
        NuoDB::Connection * nuodb_conn = cast<NuoDB::Connection>(connection->connection_handle);
        nuodb_conn->commit();
        nuodb_set_error(connection, NUODB_ZERO_ERROR, "SUCCESS");
    }
    catch (NuoDB::SQLException & e)
    {
        nuodb_set_error(connection, NUODB_CONNECTION_ERROR, e.getText());
    }

    return connection->error;
}

NUODB_CFUNC
int nuodb_rollback(
    nuodb_connection_t * connection)
{
    if (!connection)
    {
        return NUODB_ILLEGAL_ARGUMENT;
    }

    try
    {
        NuoDB::Connection * nuodb_conn = cast<NuoDB::Connection>(connection->connection_handle);
        nuodb_conn->rollback();
        nuodb_set_error(connection, NUODB_ZERO_ERROR, "SUCCESS");
    }
    catch (NuoDB::SQLException & e)
    {
        nuodb_set_error(connection, NUODB_CONNECTION_ERROR, e.getText());
    }

    return connection->error;
}

NUODB_CFUNC
int nuodb_execute(
    nuodb_connection_t * connection,
    char const * query,
    nuodb_result_t * result)
{
    if (!result)
    {
        return NUODB_ILLEGAL_ARGUMENT;
    }

    try
    {
        NuoDB::Statement * statement = cast<NuoDB::Statement>(connection->statement_handle);
        if (statement->execute(query))
        {
            result->connection_handle = connection->connection_handle;
            result->result_handle = cast<NuoDB::ResultSet>(statement->getResultSet());
        }
        else
        {
            result->result_handle = 0;
        }

        nuodb_set_error(connection, NUODB_ZERO_ERROR, "STATEMENT EXECUTED");
    }
    catch (NuoDB::SQLException & e)
    {
        printf("failed creating result set: %s\n", e.getText());
        nuodb_set_error(connection, NUODB_CONNECTION_ERROR, e.getText());
    }

    return result->connection->error;
}

NUODB_CFUNC
int nuodb_result_free(
    nuodb_result_t * result)
{
    if (!result)
    {
        return NUODB_ILLEGAL_ARGUMENT;
    }

    try
    {
        NuoDB::ResultSet * result_set = cast<NuoDB::ResultSet>(result->result_handle);
        result_set->close();
        result->result_handle = 0;
        nuodb_set_error(result->connection, NUODB_ZERO_ERROR, "RESULT SET CLOSED");
    }
    catch (NuoDB::SQLException & e)
    {
        nuodb_set_error(result->connection, NUODB_CONNECTION_ERROR, e.getText());
    }

    return result->connection->error;
}

NUODB_CFUNC
int nuodb_result_next(
    nuodb_result_t * result)
{
    if (!result)
    {
        return NUODB_ILLEGAL_ARGUMENT;
    }

    try
    {
        NuoDB::ResultSet * result_set = cast<NuoDB::ResultSet>(result->result_handle);
        if (result_set->next())
        {
            nuodb_set_error(result->connection, NUODB_ZERO_ERROR, "RESULT SET VALID");
        }
        else
        {
            nuodb_set_error(result->connection, NUODB_NO_DATA, "RESULT SET INVALID");
        }
    }
    catch (NuoDB::SQLException & e)
    {
        nuodb_set_error(result->connection, NUODB_CONNECTION_ERROR, e.getText());
    }

    return result->connection->error;
}

NUODB_CFUNC
int nuodb_result_fetch_fields(
    nuodb_result_t * result,
    size_t * column_count)
{
    if (!result)
    {
        return NUODB_ILLEGAL_ARGUMENT;
    }

    try
    {
        NuoDB::ResultSet * result_set = cast<NuoDB::ResultSet>(result->result_handle);
        NuoDB::ResultSetMetaData * metadata = result_set->getMetaData();
        *column_count = metadata->getColumnCount();
    }
    catch (NuoDB::SQLException & e)
    {
        nuodb_set_error(result->connection, NUODB_CONNECTION_ERROR, e.getText());
    }

    return result->connection->error;
}

NUODB_CFUNC
int nuodb_result_fetch_lengths(
    nuodb_result_t * result,
    size_t * lengths)
{
    if (!result)
    {
        return NUODB_ILLEGAL_ARGUMENT;
    }

    try
    {
        NuoDB::ResultSet * result_set = cast<NuoDB::ResultSet>(result->result_handle);
        NuoDB::ResultSetMetaData * metadata = result_set->getMetaData();
        size_t column_count = metadata->getColumnCount();
        for (size_t i = 0; i < column_count; i++)
        {
            lengths[i] = metadata->getColumnDisplaySize(i+1);
        }
    }
    catch (NuoDB::SQLException & e)
    {
        nuodb_set_error(result->connection, NUODB_CONNECTION_ERROR, e.getText());
    }

    return result->connection->error;
}

NUODB_CFUNC
int nuodb_result_fetch_string(
    nuodb_result_t * result,
    size_t column,
    char const ** value)
{
    if (!result)
    {
        return NUODB_ILLEGAL_ARGUMENT;
    }

    try
    {
        NuoDB::ResultSet * result_set = cast<NuoDB::ResultSet>(result->result_handle);
        *value = strdup(result_set->getString(column));
    }
    catch (NuoDB::SQLException & e)
    {
        nuodb_set_error(result->connection, NUODB_CONNECTION_ERROR, e.getText());
    }

    return result->connection->error;
}
