/**
 * Verifies the demo-critical computed outputs for Omar's seeded account:
 * predict-next confidence, expiring-doc banner, and due-reminder banner —
 * exactly what the home dashboard renders per car.
 *
 * Run: cd backend && npx tsx scripts/verify-omar.ts
 */
import { prisma } from '../src/lib/prisma';
import { predictNext } from '../src/modules/fuel/fuel.service';
import { projectNextDate } from '../src/modules/reminders/reminders.service';
import { expiring } from '../src/modules/documents/documents.service';

const EMAIL = 'abiakaromar18@outlook.com';

async function main() {
  /* eslint-disable no-console */
  const user = await prisma.user.findUnique({
    where: { email: EMAIL },
    include: { cars: { orderBy: { createdAt: 'asc' } } },
  });
  if (!user) throw new Error('user not found');
  console.log(`User: ${user.email} — ${user.cars.length} cars\n`);

  for (const car of user.cars) {
    console.log(`▸ ${car.year} ${car.make} ${car.model} [${car.plate}]  currentKm=${car.currentKm} avg=${car.avgKmPerDay}`);

    const predict = await predictNext(user.id, car.id);
    const days = predict.confidence === 'ok' ? predict.daysRemaining : null;
    console.log(`   predict-next: ${predict.confidence}` + (days != null ? ` (~${days} days, ${predict.tankRemainingLiters}L left)` : ''));

    const docs = await expiring(user.id, car.id, 30);
    console.log(`   expiring docs (banner): ${docs.length} → ` +
      docs.map((d) => {
        const dd = Math.round((d.expiryDate.getTime() - Date.now()) / 86_400_000);
        return `${d.type}:${dd >= 0 ? `${dd}d` : `EXPIRED ${-dd}d`}`;
      }).join(', '));

    const reminders = await prisma.serviceReminder.findMany({ where: { carId: car.id, isActive: true } });
    const projected = reminders
      .map((r) => ({ r, p: projectNextDate(r, car) }))
      .filter((x) => x.p)
      .map((x) => ({ type: x.r.serviceType, days: x.p!.daysRemaining }));
    const dueBanner = projected.filter((x) => x.days <= 30);
    console.log(`   due reminders (banner, ≤30d): ${dueBanner.length} → ` +
      dueBanner.map((x) => `${x.type}:${x.days >= 0 ? `${x.days}d` : `OVERDUE ${-x.days}d`}`).join(', '));
    console.log('');
  }
  /* eslint-enable no-console */
}

main().catch((e) => { console.error(e); process.exit(1); }).finally(() => prisma.$disconnect());
