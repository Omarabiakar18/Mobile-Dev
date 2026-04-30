-- CreateEnum
CREATE TYPE "FuelType" AS ENUM ('gasoline', 'diesel');

-- CreateEnum
CREATE TYPE "MaintenanceType" AS ENUM ('oil', 'brakes', 'tires', 'filter', 'battery', 'other');

-- CreateEnum
CREATE TYPE "DocumentType" AS ENUM ('insurance', 'mecanique', 'registration', 'other');

-- CreateTable
CREATE TABLE "users" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "phone" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refresh_tokens" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cars" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "make" TEXT NOT NULL,
    "model" TEXT NOT NULL,
    "year" INTEGER NOT NULL,
    "plate" TEXT NOT NULL,
    "color" TEXT,
    "currentKm" INTEGER NOT NULL DEFAULT 0,
    "fuelType" "FuelType" NOT NULL,
    "tankSize" DECIMAL(6,2) NOT NULL,
    "photoUrl" TEXT,
    "avgKmPerDay" DECIMAL(8,2),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "cars_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "fuel_entries" (
    "id" TEXT NOT NULL,
    "carId" TEXT NOT NULL,
    "date" TIMESTAMP(3) NOT NULL,
    "odometer" INTEGER NOT NULL,
    "liters" DECIMAL(8,3) NOT NULL,
    "pricePerLiter" DECIMAL(10,4) NOT NULL,
    "totalCost" DECIMAL(18,4) NOT NULL,
    "fuelType" "FuelType" NOT NULL,
    "station" TEXT,
    "isFullTank" BOOLEAN NOT NULL DEFAULT false,
    "receiptPhotoUrl" TEXT,
    "latitude" DOUBLE PRECISION,
    "longitude" DOUBLE PRECISION,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "fuel_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "maintenance_entries" (
    "id" TEXT NOT NULL,
    "carId" TEXT NOT NULL,
    "date" TIMESTAMP(3) NOT NULL,
    "km" INTEGER NOT NULL,
    "type" "MaintenanceType" NOT NULL,
    "description" TEXT,
    "cost" DECIMAL(18,4) NOT NULL,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "maintenance_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "maintenance_photos" (
    "id" TEXT NOT NULL,
    "maintenanceEntryId" TEXT NOT NULL,
    "url" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "maintenance_photos_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "documents" (
    "id" TEXT NOT NULL,
    "carId" TEXT NOT NULL,
    "type" "DocumentType" NOT NULL,
    "issuedDate" TIMESTAMP(3),
    "expiryDate" TIMESTAMP(3) NOT NULL,
    "fileUrl" TEXT NOT NULL,
    "issuer" TEXT,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "documents_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "service_reminders" (
    "id" TEXT NOT NULL,
    "carId" TEXT NOT NULL,
    "serviceType" TEXT NOT NULL,
    "lastDoneKm" INTEGER NOT NULL,
    "lastDoneDate" TIMESTAMP(3) NOT NULL,
    "intervalKm" INTEGER,
    "intervalMonths" INTEGER,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "lastNotifiedAt" TIMESTAMP(3),
    "aiMessage" TEXT,
    "aiMessageGeneratedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "service_reminders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "gas_stations" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "latitude" DOUBLE PRECISION NOT NULL,
    "longitude" DOUBLE PRECISION NOT NULL,
    "city" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "gas_stations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ocr_cache" (
    "id" TEXT NOT NULL,
    "imageHash" TEXT NOT NULL,
    "fields" JSONB NOT NULL,
    "confidence" JSONB NOT NULL,
    "rawText" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ocr_cache_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE UNIQUE INDEX "refresh_tokens_tokenHash_key" ON "refresh_tokens"("tokenHash");

-- CreateIndex
CREATE INDEX "refresh_tokens_userId_expiresAt_idx" ON "refresh_tokens"("userId", "expiresAt");

-- CreateIndex
CREATE INDEX "cars_userId_idx" ON "cars"("userId");

-- CreateIndex
CREATE INDEX "fuel_entries_carId_date_idx" ON "fuel_entries"("carId", "date");

-- CreateIndex
CREATE INDEX "maintenance_entries_carId_date_idx" ON "maintenance_entries"("carId", "date");

-- CreateIndex
CREATE INDEX "maintenance_photos_maintenanceEntryId_idx" ON "maintenance_photos"("maintenanceEntryId");

-- CreateIndex
CREATE INDEX "documents_carId_expiryDate_idx" ON "documents"("carId", "expiryDate");

-- CreateIndex
CREATE INDEX "service_reminders_carId_isActive_idx" ON "service_reminders"("carId", "isActive");

-- CreateIndex
CREATE INDEX "gas_stations_latitude_longitude_idx" ON "gas_stations"("latitude", "longitude");

-- CreateIndex
CREATE UNIQUE INDEX "ocr_cache_imageHash_key" ON "ocr_cache"("imageHash");

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cars" ADD CONSTRAINT "cars_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "fuel_entries" ADD CONSTRAINT "fuel_entries_carId_fkey" FOREIGN KEY ("carId") REFERENCES "cars"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "maintenance_entries" ADD CONSTRAINT "maintenance_entries_carId_fkey" FOREIGN KEY ("carId") REFERENCES "cars"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "maintenance_photos" ADD CONSTRAINT "maintenance_photos_maintenanceEntryId_fkey" FOREIGN KEY ("maintenanceEntryId") REFERENCES "maintenance_entries"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "documents" ADD CONSTRAINT "documents_carId_fkey" FOREIGN KEY ("carId") REFERENCES "cars"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_reminders" ADD CONSTRAINT "service_reminders_carId_fkey" FOREIGN KEY ("carId") REFERENCES "cars"("id") ON DELETE CASCADE ON UPDATE CASCADE;
