CREATE DATABASE EnglishVocabularyTraining;
GO

USE EnglishVocabularyTraining;
GO

-- =============================================
-- 1. WordType
-- =============================================
CREATE TABLE WordType (
    WordTypeId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL UNIQUE
);
GO


-- =============================================
-- 2. Topic
-- =============================================
CREATE TABLE Topic (
    TopicId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL UNIQUE
);
GO


-- =============================================
-- 3. Vocabulary
-- =============================================
CREATE TABLE Vocabulary (
    VocabularyId INT IDENTITY(1,1) PRIMARY KEY,
    Word NVARCHAR(100) NOT NULL,
    Meaning NVARCHAR(500) NOT NULL,
    WordTypeId INT NOT NULL,
    TopicId INT NOT NULL,

    CONSTRAINT FK_Vocabulary_WordType
        FOREIGN KEY (WordTypeId)
        REFERENCES WordType(WordTypeId),

    CONSTRAINT FK_Vocabulary_Topic
        FOREIGN KEY (TopicId)
        REFERENCES Topic(TopicId)
);
GO


-- =============================================
-- 4. Quiz
-- =============================================
CREATE TABLE Quiz (
    QuizId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(200) NOT NULL,
    TopicId INT NULL,

    CONSTRAINT FK_Quiz_Topic
        FOREIGN KEY (TopicId)
        REFERENCES Topic(TopicId)
);
GO


-- =============================================
-- 5. QuizQuestion
-- =============================================
CREATE TABLE QuizQuestion (
    QuestionId INT IDENTITY(1,1) PRIMARY KEY,
    QuizId INT NOT NULL,
    VocabularyId INT NOT NULL,
    QuestionType NVARCHAR(50) NOT NULL,

    CONSTRAINT FK_QuizQuestion_Quiz
        FOREIGN KEY (QuizId)
        REFERENCES Quiz(QuizId),

    CONSTRAINT FK_QuizQuestion_Vocabulary
        FOREIGN KEY (VocabularyId)
        REFERENCES Vocabulary(VocabularyId)
);
GO


-- =============================================
-- Seed Word Types
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
-- Seed Topics
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



USE EnglishVocabularyTraining;
GO

-- 1. Data rules
ALTER TABLE Vocabulary   ADD CONSTRAINT UQ_Vocabulary_Word_WordType UNIQUE (Word, WordTypeId);
ALTER TABLE QuizQuestion ADD CONSTRAINT UQ_QuizQuestion_Quiz_Vocabulary UNIQUE (QuizId, VocabularyId);
ALTER TABLE Topic        ADD CONSTRAINT CK_Topic_Name_NotBlank    CHECK (LEN(LTRIM(Name)) > 0);
ALTER TABLE WordType     ADD CONSTRAINT CK_WordType_Name_NotBlank CHECK (LEN(LTRIM(Name)) > 0);
ALTER TABLE Vocabulary   ADD CONSTRAINT CK_Vocabulary_Word_NotBlank CHECK (LEN(LTRIM(Word)) > 0);
ALTER TABLE QuizQuestion ADD CONSTRAINT CK_QuizQuestion_Type
    CHECK (QuestionType IN (N'MultipleChoice', N'FillInBlank', N'Translate'));
GO

-- 2. Indexes on foreign keys
CREATE INDEX IX_Vocabulary_TopicId        ON Vocabulary(TopicId);
CREATE INDEX IX_Vocabulary_WordTypeId     ON Vocabulary(WordTypeId);
CREATE INDEX IX_Quiz_TopicId              ON Quiz(TopicId);
CREATE INDEX IX_QuizQuestion_VocabularyId ON QuizQuestion(VocabularyId);
-- (QuizQuestion.QuizId is already covered by UQ_QuizQuestion_Quiz_Vocabulary)
GO

-- 3. Deleting a quiz deletes its questions
ALTER TABLE QuizQuestion DROP CONSTRAINT FK_QuizQuestion_Quiz;
ALTER TABLE QuizQuestion ADD CONSTRAINT FK_QuizQuestion_Quiz
    FOREIGN KEY (QuizId) REFERENCES Quiz(QuizId) ON DELETE CASCADE;
GO

-- 5. Extra word details (nullable / defaulted, so the current API keeps working)
ALTER TABLE Vocabulary ADD
    Pronunciation NVARCHAR(100) NULL,
    Example       NVARCHAR(500) NULL,
    CreatedAt     DATETIME2 NOT NULL CONSTRAINT DF_Vocabulary_CreatedAt DEFAULT SYSUTCDATETIME();
GO

-- Sample words to test with
INSERT INTO Vocabulary (Word, Meaning, WordTypeId, TopicId) VALUES
    (N'breakfast', N'bữa sáng',     1, 1),
    (N'passport',  N'hộ chiếu',     1, 2),
    (N'negotiate', N'đàm phán',     2, 3),
    (N'download',  N'tải xuống',    2, 4),
    (N'healthy',   N'khỏe mạnh',    3, 6),
    (N'delicious', N'ngon',         3, 7),
    (N'quickly',   N'một cách nhanh', 4, 1);
GO
