-- CreateTable
CREATE TABLE "PracticeSession" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "scoreId" TEXT NOT NULL,
    "startedAt" DATETIME NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'ACTIVE',
    "noteEvents" TEXT NOT NULL DEFAULT '[]',
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "PracticeSession_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "PracticeSession_scoreId_fkey" FOREIGN KEY ("scoreId") REFERENCES "Score" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX "PracticeSession_userId_idx" ON "PracticeSession"("userId");
CREATE INDEX "PracticeSession_scoreId_idx" ON "PracticeSession"("scoreId");
CREATE INDEX "PracticeSession_status_idx" ON "PracticeSession"("status");
