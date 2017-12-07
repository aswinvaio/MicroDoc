CREATE TABLE [dbo].[DBVersionInfo] (
    [ID]                    INT            IDENTITY (1, 1) NOT NULL,
    [VersionNo]             INT            NOT NULL,
    [UpgradeScriptFileName] NVARCHAR (500) NULL,
    [CreatedDate]           DATETIME       NOT NULL,
    CONSTRAINT [PK_DBVersionInfo] PRIMARY KEY CLUSTERED ([ID] ASC)
);

