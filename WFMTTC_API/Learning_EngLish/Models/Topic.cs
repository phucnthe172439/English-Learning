using System;
using System.Collections.Generic;

namespace Learning_EngLish.Models;

public partial class Topic
{
    public int TopicId { get; set; }

    public string Name { get; set; } = null!;

    public virtual ICollection<Quiz> Quizzes { get; set; } = new List<Quiz>();

    public virtual ICollection<Vocabulary> Vocabularies { get; set; } = new List<Vocabulary>();
}
