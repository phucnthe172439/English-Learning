using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace Learning_EngLish.Data;

/// <summary>
/// Health check for /health: Healthy when SQL Server answers a trivial query, Unhealthy otherwise.
/// Uses the app's connection string with short timeouts, so /health answers within a few seconds
/// when the database is down or stuck (defaults: 15 s to connect, 30 s per query, and SqlClient
/// doesn't cancel a pending open).
/// </summary>
public class DatabaseHealthCheck : IHealthCheck
{
    private readonly string _connectionString;

    public DatabaseHealthCheck(IConfiguration configuration)
    {
        var builder = new SqlConnectionStringBuilder(
            configuration.GetConnectionString("DefaultConnection")
            ?? throw new InvalidOperationException("Connection string 'DefaultConnection' is missing."))
        {
            ConnectTimeout = 3
        };
        _connectionString = builder.ConnectionString;
    }

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        try
        {
            await using var connection = new SqlConnection(_connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand("SELECT 1", connection) { CommandTimeout = 3 };
            await command.ExecuteScalarAsync(cancellationToken);
            return HealthCheckResult.Healthy("SQL Server is reachable.");
        }
        catch (Exception ex)
        {
            // The exception is logged by the health check service; the HTTP response only shows the status.
            return HealthCheckResult.Unhealthy("Cannot reach SQL Server.", ex);
        }
    }
}
