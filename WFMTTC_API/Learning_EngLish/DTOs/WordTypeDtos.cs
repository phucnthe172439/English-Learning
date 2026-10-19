using System.ComponentModel.DataAnnotations;

namespace Learning_EngLish.DTOs;

public record WordTypeResponse(int WordTypeId, string Name, int VocabularyCount);

public class WordTypeRequest
{
    [Required, StringLength(50)]
    public string Name { get; set; } = "";
}
