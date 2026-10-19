using System;
using System.Collections.Generic;

namespace Learning_EngLish.Models;

public partial class QuizQuestion
{
    public int QuestionId { get; set; }

    public int QuizId { get; set; }

    public int VocabularyId { get; set; }

    public string QuestionType { get; set; } = null!;

    public virtual Quiz Quiz { get; set; } = null!;

    public virtual Vocabulary Vocabulary { get; set; } = null!;
}
