-- CreateTable
CREATE TABLE "Score" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "title" TEXT NOT NULL,
    "composer" TEXT NOT NULL,
    "arranger" TEXT,
    "difficulty" TEXT NOT NULL DEFAULT 'BEGINNER',
    "musicXmlPath" TEXT NOT NULL,
    "coverImage" TEXT,
    "fileSize" INTEGER NOT NULL,
    "duration" INTEGER NOT NULL,
    "measures" INTEGER NOT NULL,
    "timeSignature" TEXT NOT NULL DEFAULT '4/4',
    "keySignature" TEXT NOT NULL DEFAULT 'C Major',
    "tempo" INTEGER NOT NULL DEFAULT 120,
    "category" TEXT,
    "playCount" INTEGER NOT NULL DEFAULT 0,
    "favoriteCount" INTEGER NOT NULL DEFAULT 0,
    "status" TEXT NOT NULL DEFAULT 'DRAFT',
    "isPublic" BOOLEAN NOT NULL DEFAULT true,
    "source" TEXT,
    "license" TEXT,
    "copyright" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    "publishedAt" DATETIME
);

-- CreateTable
CREATE TABLE "Tag" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "name" TEXT NOT NULL
);

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "email" TEXT NOT NULL,
    "password" TEXT NOT NULL,
    "nickname" TEXT,
    "avatar" TEXT,
    "totalPracticeTime" INTEGER NOT NULL DEFAULT 0,
    "totalSessions" INTEGER NOT NULL DEFAULT 0,
    "totalNotes" INTEGER NOT NULL DEFAULT 0,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL
);

-- CreateTable
CREATE TABLE "PracticeRecord" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "scoreId" TEXT NOT NULL,
    "duration" INTEGER NOT NULL,
    "notesPlayed" INTEGER NOT NULL,
    "pitchScore" REAL NOT NULL,
    "rhythmScore" REAL NOT NULL,
    "overallScore" REAL NOT NULL,
    "grade" TEXT NOT NULL,
    "details" TEXT,
    "startedAt" DATETIME NOT NULL,
    "completedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "PracticeRecord_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "PracticeRecord_scoreId_fkey" FOREIGN KEY ("scoreId") REFERENCES "Score" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "Device" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT,
    "name" TEXT NOT NULL,
    "manufacturer" TEXT,
    "model" TEXT,
    "lastConnected" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- CreateTable
CREATE TABLE "_ScoreToTag" (
    "A" TEXT NOT NULL,
    "B" TEXT NOT NULL,
    CONSTRAINT "_ScoreToTag_A_fkey" FOREIGN KEY ("A") REFERENCES "Score" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "_ScoreToTag_B_fkey" FOREIGN KEY ("B") REFERENCES "Tag" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "_UserFavorites" (
    "A" TEXT NOT NULL,
    "B" TEXT NOT NULL,
    CONSTRAINT "_UserFavorites_A_fkey" FOREIGN KEY ("A") REFERENCES "Score" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "_UserFavorites_B_fkey" FOREIGN KEY ("B") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateIndex
CREATE INDEX "Score_title_idx" ON "Score"("title");

-- CreateIndex
CREATE INDEX "Score_composer_idx" ON "Score"("composer");

-- CreateIndex
CREATE INDEX "Score_difficulty_idx" ON "Score"("difficulty");

-- CreateIndex
CREATE INDEX "Score_category_idx" ON "Score"("category");

-- CreateIndex
CREATE UNIQUE INDEX "Tag_name_key" ON "Tag"("name");

-- CreateIndex
CREATE INDEX "Tag_name_idx" ON "Tag"("name");

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE INDEX "PracticeRecord_userId_idx" ON "PracticeRecord"("userId");

-- CreateIndex
CREATE INDEX "PracticeRecord_scoreId_idx" ON "PracticeRecord"("scoreId");

-- CreateIndex
CREATE INDEX "PracticeRecord_completedAt_idx" ON "PracticeRecord"("completedAt");

-- CreateIndex
CREATE UNIQUE INDEX "_ScoreToTag_AB_unique" ON "_ScoreToTag"("A", "B");

-- CreateIndex
CREATE INDEX "_ScoreToTag_B_index" ON "_ScoreToTag"("B");

-- CreateIndex
CREATE UNIQUE INDEX "_UserFavorites_AB_unique" ON "_UserFavorites"("A", "B");

-- CreateIndex
CREATE INDEX "_UserFavorites_B_index" ON "_UserFavorites"("B");
