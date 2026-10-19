using System;
using System.Collections.Generic;

namespace Learning_EngLish.Models;

public partial class Quiz
{
    public int QuizId { get; set; }

    public string Name { get; set; } = null!;

    public int? TopicId { get; set; }

    public virtual ICollection<QuizQuestion> QuizQuestions { get; set; } = new List<QuizQuestion>();

    public virtual Topic? Topic { get; set; }
}
