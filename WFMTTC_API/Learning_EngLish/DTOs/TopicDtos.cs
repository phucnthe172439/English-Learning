using System.ComponentModel.DataAnnotations;

namespace Learning_EngLish.DTOs;

public record TopicResponse(int TopicId, string Name, int VocabularyCount);

public class TopicRequest
{
    [Required, StringLength(100)]
    public string Name { get; set; } = "";
}
