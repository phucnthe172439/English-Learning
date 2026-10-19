namespace Learning_EngLish.Data;

/// <summary>SQL Server error numbers we react to (SqlException.Number).</summary>
public static class SqlErrors
{
    /// <summary>FOREIGN KEY violation: inserting a non-existent TopicId, or deleting a row that is still referenced.</summary>
    public const int ForeignKeyViolation = 547;

    /// <summary>UNIQUE constraint violation (e.g. two topics with the same Name).</summary>
    public const int UniqueConstraintViolation = 2627;

    /// <summary>UNIQUE index violation (same idea as 2627, raised for unique indexes).</summary>
    public const int UniqueIndexViolation = 2601;

    public static bool IsDuplicate(int number) =>
        number is UniqueConstraintViolation or UniqueIndexViolation;
}
