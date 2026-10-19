using System.Data;
using Learning_EngLish.Data;
using Learning_EngLish.DTOs;
using Microsoft.Data.SqlClient;

namespace Learning_EngLish.Repositories;

/// <summary>SQL for the WordType table (noun, verb, adjective...). Same pattern as TopicRepository.</summary>
public class WordTypeRepository
{
    private readonly SqlConnectionFactory _db;

    public WordTypeRepository(SqlConnectionFactory db)
    {
        _db = db;
    }

    private const string SelectSql = """
        SELECT w.WordTypeId, w.Name, COUNT(v.VocabularyId) AS VocabularyCount
        FROM WordType w
        LEFT JOIN Vocabulary v ON v.WordTypeId = w.WordTypeId
        """;

    private const string GroupBySql = "\nGROUP BY w.WordTypeId, w.Name";

    public async Task<List<WordTypeResponse>> GetAllAsync()
    {
        const string sql = SelectSql + GroupBySql + "\nORDER BY w.Name";

        await using var connection = await _db.OpenAsync();
        await using var command = new SqlCommand(sql, connection);

        var result = new List<WordTypeResponse>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            result.Add(Map(reader));
        }
        return result;
    }

    public async Task<WordTypeResponse?> GetByIdAsync(int id)
    {
        const string sql = SelectSql + "\nWHERE w.WordTypeId = @Id" + GroupBySql;

        await using var connection = await _db.OpenAsync();
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@Id", SqlDbType.Int).Value = id;

        await using var reader = await command.ExecuteReaderAsync();
        return await reader.ReadAsync() ? Map(reader) : null;
    }

    public async Task<int> CreateAsync(WordTypeRequest request)
    {
        const string sql = "INSERT INTO WordType (Name) OUTPUT INSERTED.WordTypeId VALUES (@Name)";

        await using var connection = await _db.OpenAsync();
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@Name", SqlDbType.NVarChar, 50).Value = request.Name.Trim();

        return (int)(await command.ExecuteScalarAsync())!;
    }

    public async Task<bool> UpdateAsync(int id, WordTypeRequest request)
    {
        const string sql = "UPDATE WordType SET Name = @Name WHERE WordTypeId = @Id";

        await using var connection = await _db.OpenAsync();
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@Id", SqlDbType.Int).Value = id;
        command.Parameters.Add("@Name", SqlDbType.NVarChar, 50).Value = request.Name.Trim();

        return await command.ExecuteNonQueryAsync() > 0;
    }

    public async Task<bool> DeleteAsync(int id)
    {
        const string sql = "DELETE FROM WordType WHERE WordTypeId = @Id";

        await using var connection = await _db.OpenAsync();
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@Id", SqlDbType.Int).Value = id;

        return await command.ExecuteNonQueryAsync() > 0;
    }

    private static WordTypeResponse Map(SqlDataReader reader) => new(
        reader.GetInt32(reader.GetOrdinal("WordTypeId")),
        reader.GetString(reader.GetOrdinal("Name")),
        reader.GetInt32(reader.GetOrdinal("VocabularyCount")));
}
