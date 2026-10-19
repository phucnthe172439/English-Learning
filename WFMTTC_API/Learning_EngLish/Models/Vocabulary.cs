using System;
using System.Collections.Generic;

namespace Learning_EngLish.Models;

public partial class Vocabulary
{
    public int VocabularyId { get; set; }

    public string Word { get; set; } = null!;

    public string Meaning { get; set; } = null!;

    public int WordTypeId { get; set; }

    public int TopicId { get; set; }

    public virtual ICollection<QuizQuestion> QuizQuestions { get; set; } = new List<QuizQuestion>();

    public virtual Topic Topic { get; set; } = null!;

    public virtual WordType WordType { get; set; } = null!;
}
