using System;
using System.Collections.Generic;

namespace Learning_EngLish.Models;

public partial class WordType
{
    public int WordTypeId { get; set; }

    public string Name { get; set; } = null!;

    public virtual ICollection<Vocabulary> Vocabularies { get; set; } = new List<Vocabulary>();
}
