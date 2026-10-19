using Microsoft.Data.SqlClient;

namespace Learning_EngLish.Data;

/// <summary>
/// Creates open connections to SQL Server.
/// ADO.NET pools connections behind the scenes, so opening one per request is cheap.
/// Always dispose them (await using) so they go back to the pool.
/// </summary>
public class SqlConnectionFactory
{
    private readonly string _connectionString;

    public SqlConnectionFactory(IConfiguration configuration)
    {
        _connectionString = configuration.GetConnectionString("DefaultConnection")
            ?? throw new InvalidOperationException("Connection string 'DefaultConnection' is missing.");
    }

    public async Task<SqlConnection> OpenAsync()
    {
        var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync();
        return connection;
    }
}
