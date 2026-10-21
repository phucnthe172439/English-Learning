-- =============================================
-- EnglishVocabularyTraining: starter data
-- Run by init-db.sh when all tables are empty. One transaction: all rows or none.
-- =============================================

USE EnglishVocabularyTraining;
GO

SET XACT_ABORT ON;
BEGIN TRANSACTION;
GO

-- =============================================
-- Word types
-- =============================================
INSERT INTO WordType (Name)
VALUES
    (N'Noun'),
    (N'Verb'),
    (N'Adjective'),
    (N'Adverb'),
    (N'Preposition'),
    (N'Pronoun'),
    (N'Conjunction'),
    (N'Interjection');
GO

-- =============================================
-- Topics
-- =============================================
INSERT INTO Topic (Name)
VALUES
    (N'Daily Life'),
    (N'Travel'),
    (N'Business'),
    (N'Technology'),
    (N'Education'),
    (N'Health'),
    (N'Food'),
    (N'Environment'),
    (N'Sports'),
    (N'Entertainment');
GO

-- =============================================
-- Sample words to test with
-- (looked up by name, so they don't depend on identity values)
-- =============================================
INSERT INTO Vocabulary (Word, Meaning, WordTypeId, TopicId)
SELECT s.Word, s.Meaning, w.WordTypeId, t.TopicId
FROM (VALUES
    (N'breakfast', N'bữa sáng',       N'Noun',      N'Daily Life'),
    (N'passport',  N'hộ chiếu',       N'Noun',      N'Travel'),
    (N'negotiate', N'đàm phán',       N'Verb',      N'Business'),
    (N'download',  N'tải xuống',      N'Verb',      N'Technology'),
    (N'healthy',   N'khỏe mạnh',      N'Adjective', N'Health'),
    (N'delicious', N'ngon',           N'Adjective', N'Food'),
    (N'quickly',   N'một cách nhanh', N'Adverb',    N'Daily Life')
) AS s (Word, Meaning, WordTypeName, TopicName)
JOIN WordType w ON w.Name = s.WordTypeName
JOIN Topic    t ON t.Name = s.TopicName;
GO

COMMIT TRANSACTION;
GO
