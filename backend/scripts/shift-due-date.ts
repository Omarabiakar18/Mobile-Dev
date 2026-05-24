/**
 * Shifts a document expiry (or a reminder lastDoneDate) so the
 * SchedulingSync code computes a notification firing time `--seconds` from
 * now. Run from the host while the app is on the phone; then trigger
 * "Force schedule resync" in the app's Settings → Debug tools to push the
 * new schedule.
 *
 * Usage:
 *   npx tsx scripts/shift-due-date.ts --kind=doc --id=<uuid> --seconds=120
 *   npx tsx scripts/shift-due-date.ts --kind=reminder --id=<uuid> --seconds=120
 *
 * For documents the script targets the -30d notification: expiryDate is set
 * to (now + 30d + seconds), so the scheduler will fire in approximately
 * `seconds` time. For reminders it does the same on the calendar leg.
 */
import { prisma } from '../src/lib/prisma';

const args = process.argv.slice(2).reduce<Record<string, string>>((acc, a) => {
  const m = a.match(/^--([^=]+)=(.*)$/);
  if (m) acc[m[1]] = m[2];
  return acc;
}, {});

const kind = args.kind ?? 'doc';
const id = args.id;
const seconds = parseInt(args.seconds ?? '120', 10);

if (!id) {
  console.error('Missing --id=<uuid>');
  process.exit(1);
}

async function main() {
  const fireAt = new Date(Date.now() + seconds * 1000);
  const targetDue = new Date(fireAt.getTime() + 30 * 24 * 60 * 60 * 1000);

  if (kind === 'doc') {
    const doc = await prisma.document.update({
      where: { id },
      data: { expiryDate: targetDue },
    });
    console.log(`Document ${doc.id} expiryDate set to ${doc.expiryDate.toISOString()}`);
    console.log(`-> -30d notification should fire ~${fireAt.toISOString()}`);
  } else if (kind === 'reminder') {
    const r = await prisma.serviceReminder.findUnique({ where: { id } });
    if (!r) throw new Error('Reminder not found');
    const months = r.intervalMonths ?? 6;
    const lastDone = new Date(targetDue);
    lastDone.setMonth(lastDone.getMonth() - months);
    const updated = await prisma.serviceReminder.update({
      where: { id },
      data: { lastDoneDate: lastDone, intervalKm: null, intervalMonths: months },
    });
    console.log(`Reminder ${updated.id} adjusted: lastDoneDate=${lastDone.toISOString()}, intervalMonths=${months}`);
    console.log(`-> -30d notification should fire ~${fireAt.toISOString()}`);
  } else {
    console.error(`Unknown --kind=${kind}; expected doc|reminder`);
    process.exit(1);
  }

  console.log('Now tap Settings → Debug tools → Force schedule resync on the phone.');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
