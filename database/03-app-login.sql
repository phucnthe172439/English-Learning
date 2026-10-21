-- =============================================
-- Login used by the API (english_app)
--
-- Runs on every start of the db-init container, so it is safe to re-run:
--   * creates the login and the database user if they're missing,
--   * resets the password to APP_DB_PASSWORD from .env,
--   * re-links the user after a .bak restore (a restored user is "orphaned":
--     its SID belongs to the login on the PC, not to the one in the container).
--
-- $(APP_DB_PASSWORD) is a sqlcmd variable, passed in by init-db.sh.
-- =============================================

USE master;
GO

IF SUSER_ID(N'english_app') IS NULL
    CREATE LOGIN english_app WITH PASSWORD = N'$(APP_DB_PASSWORD)';
ELSE
    ALTER LOGIN english_app WITH PASSWORD = N'$(APP_DB_PASSWORD)';
GO

USE EnglishVocabularyTraining;
GO

IF USER_ID(N'english_app') IS NULL
    CREATE USER english_app FOR LOGIN english_app;
ELSE
    ALTER USER english_app WITH LOGIN = english_app;
GO

-- Read and write data only. The API never changes the schema, so it doesn't need db_owner.
ALTER ROLE db_datareader ADD MEMBER english_app;
ALTER ROLE db_datawriter ADD MEMBER english_app;
GO
