using System.Data;
using Learning_EngLish.Data;
using Learning_EngLish.DTOs;
using Microsoft.Data.SqlClient;

namespace Learning_EngLish.Repositories;

/// <summary>SQL for the Topic table. Same pattern as VocabularyRepository.</summary>
public class TopicRepository
{
    private readonly SqlConnectionFactory _db;

    public TopicRepository(SqlConnectionFactory db)
    {
        _db = db;
    }

    // LEFT JOIN + GROUP BY: every topic appears, even ones with 0 words.
    private const string SelectSql = """
        SELECT t.TopicId, t.Name, COUNT(v.VocabularyId) AS VocabularyCount
        FROM Topic t
        LEFT JOIN Vocabulary v ON v.TopicId = t.TopicId
        """;

    private const string GroupBySql = "\nGROUP BY t.TopicId, t.Name";

    public async Task<List<TopicResponse>> GetAllAsync()
    {
        const string sql = SelectSql + GroupBySql + "\nORDER BY t.Name";

        await using var connection = await _db.OpenAsync();
        await using var command = new SqlCommand(sql, connection);

        var result = new List<TopicResponse>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            result.Add(Map(reader));
        }
        return result;
    }

    public async Task<TopicResponse?> GetByIdAsync(int id)
    {
        const string sql = SelectSql + "\nWHERE t.TopicId = @Id" + GroupBySql;

        await using var connection = await _db.OpenAsync();
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@Id", SqlDbType.Int).Value = id;

        await using var reader = await command.ExecuteReaderAsync();
        return await reader.ReadAsync() ? Map(reader) : null;
    }

    public async Task<int> CreateAsync(TopicRequest request)
    {
        const string sql = "INSERT INTO Topic (Name) OUTPUT INSERTED.TopicId VALUES (@Name)";

        await using var connection = await _db.OpenAsync();
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@Name", SqlDbType.NVarChar, 100).Value = request.Name.Trim();

        return (int)(await command.ExecuteScalarAsync())!;
    }

    public async Task<bool> UpdateAsync(int id, TopicRequest request)
    {
        const string sql = "UPDATE Topic SET Name = @Name WHERE TopicId = @Id";

        await using var connection = await _db.OpenAsync();
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@Id", SqlDbType.Int).Value = id;
        command.Parameters.Add("@Name", SqlDbType.NVarChar, 100).Value = request.Name.Trim();

        return await command.ExecuteNonQueryAsync() > 0;
    }

    public async Task<bool> DeleteAsync(int id)
    {
        const string sql = "DELETE FROM Topic WHERE TopicId = @Id";

        await using var connection = await _db.OpenAsync();
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@Id", SqlDbType.Int).Value = id;

        return await command.ExecuteNonQueryAsync() > 0;
    }

    private static TopicResponse Map(SqlDataReader reader) => new(
        reader.GetInt32(reader.GetOrdinal("TopicId")),
        reader.GetString(reader.GetOrdinal("Name")),
        reader.GetInt32(reader.GetOrdinal("VocabularyCount")));
}
