-- =============================================
-- EnglishVocabularyTraining: schema (tables, constraints, indexes)
--
-- Docker: run by database/init-db.sh when the database has no tables yet.
-- Manual: run it in DBeaver/SSMS on a server that doesn't have the tables.
-- Column order and constraint names match the database built by the
-- original script, so a .bak restore and this script give the same schema.
--
-- All tables are created in ONE transaction: if any statement fails, everything
-- is rolled back, so the database is never left with only some of the tables.
-- =============================================

IF DB_ID(N'EnglishVocabularyTraining') IS NULL
    CREATE DATABASE EnglishVocabularyTraining;   -- can't be inside a transaction
GO

USE EnglishVocabularyTraining;
GO

SET XACT_ABORT ON;    -- any error rolls back the whole transaction
BEGIN TRANSACTION;
GO

-- =============================================
-- 1. WordType
-- =============================================
CREATE TABLE WordType (
    WordTypeId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL UNIQUE,

    CONSTRAINT CK_WordType_Name_NotBlank CHECK (LEN(LTRIM(Name)) > 0)
);
GO

-- =============================================
-- 2. Topic
-- =============================================
CREATE TABLE Topic (
    TopicId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL UNIQUE,

    CONSTRAINT CK_Topic_Name_NotBlank CHECK (LEN(LTRIM(Name)) > 0)
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
    Pronunciation NVARCHAR(100) NULL,
    Example NVARCHAR(500) NULL,
    CreatedAt DATETIME2 NOT NULL
        CONSTRAINT DF_Vocabulary_CreatedAt DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_Vocabulary_WordType
        FOREIGN KEY (WordTypeId)
        REFERENCES WordType(WordTypeId),

    CONSTRAINT FK_Vocabulary_Topic
        FOREIGN KEY (TopicId)
        REFERENCES Topic(TopicId),

    CONSTRAINT UQ_Vocabulary_Word_WordType UNIQUE (Word, WordTypeId),
    CONSTRAINT CK_Vocabulary_Word_NotBlank CHECK (LEN(LTRIM(Word)) > 0)
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

    -- Deleting a quiz deletes its questions
    CONSTRAINT FK_QuizQuestion_Quiz
        FOREIGN KEY (QuizId)
        REFERENCES Quiz(QuizId)
        ON DELETE CASCADE,

    CONSTRAINT FK_QuizQuestion_Vocabulary
        FOREIGN KEY (VocabularyId)
        REFERENCES Vocabulary(VocabularyId),

    CONSTRAINT UQ_QuizQuestion_Quiz_Vocabulary UNIQUE (QuizId, VocabularyId),
    CONSTRAINT CK_QuizQuestion_Type
        CHECK (QuestionType IN (N'MultipleChoice', N'FillInBlank', N'Translate'))
);
GO

-- =============================================
-- 6. Indexes on foreign keys
-- (QuizQuestion.QuizId is already covered by UQ_QuizQuestion_Quiz_Vocabulary)
-- =============================================
CREATE INDEX IX_Vocabulary_TopicId        ON Vocabulary(TopicId);
CREATE INDEX IX_Vocabulary_WordTypeId     ON Vocabulary(WordTypeId);
CREATE INDEX IX_Quiz_TopicId              ON Quiz(TopicId);
CREATE INDEX IX_QuizQuestion_VocabularyId ON QuizQuestion(VocabularyId);
GO

COMMIT TRANSACTION;
GO
