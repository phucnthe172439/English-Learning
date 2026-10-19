using System.ComponentModel.DataAnnotations;

namespace Learning_EngLish.DTOs;

/// <summary>What the API returns for a vocabulary row (joined with Topic and WordType names).</summary>
public record VocabularyResponse(
    int VocabularyId,
    string Word,
    string Meaning,
    int WordTypeId,
    string WordTypeName,
    int TopicId,
    string TopicName);

/// <summary>What the client sends to create or update a vocabulary.</summary>
public class VocabularyRequest
{
    [Required, StringLength(100)]
    public string Word { get; set; } = "";

    [Required, StringLength(500)]
    public string Meaning { get; set; } = "";

    [Range(1, int.MaxValue)]
    public int WordTypeId { get; set; }

    [Range(1, int.MaxValue)]
    public int TopicId { get; set; }
}
