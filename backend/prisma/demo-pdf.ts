/**
 * Minimal, dependency-free PDF generator for demo document blobs.
 *
 * The seed creates Document rows whose fileUrl points at
 * `/uploads/demo/<type>.pdf`. The mobile "Open file" button launches that URL,
 * so those blobs must actually exist on disk or the in-app browser hits a 404
 * (previously surfaced as a 500). We don't want to commit binary PDFs to git,
 * so we synthesize a tiny valid single-page PDF at seed time instead.
 *
 * The output is a hand-assembled PDF 1.4 file with a byte-accurate xref table —
 * enough for SFSafariViewController (iOS) and Chrome Custom Tabs (Android) to
 * render the page. Text is ASCII-only so it maps cleanly through the standard
 * Helvetica WinAnsi encoding.
 */

/** Escapes the characters that are special inside a PDF literal string. */
function escapePdfText(s: string): string {
  return s.replace(/([\\()])/g, '\\$1');
}

/**
 * Builds a single-page PDF showing `title` (large) and an optional `subtitle`
 * (smaller). Returns the raw bytes ready to write to disk.
 */
export function buildDemoPdf(title: string, subtitle = ''): Buffer {
  const content =
    `BT /F1 24 Tf 72 720 Td (${escapePdfText(title)}) Tj ET\n` +
    (subtitle ? `BT /F1 14 Tf 72 688 Td (${escapePdfText(subtitle)}) Tj ET\n` : '');
  const contentLength = Buffer.byteLength(content, 'latin1');

  // Object bodies, in order. Object N is at index N-1.
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] ' +
      '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${contentLength} >>\nstream\n${content}endstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];

  let pdf = '%PDF-1.4\n';
  const offsets: number[] = [];
  objects.forEach((body, i) => {
    offsets.push(Buffer.byteLength(pdf, 'latin1'));
    pdf += `${i + 1} 0 obj\n${body}\nendobj\n`;
  });

  const xrefStart = Buffer.byteLength(pdf, 'latin1');
  const size = objects.length + 1; // +1 for the free object 0
  pdf += `xref\n0 ${size}\n`;
  pdf += '0000000000 65535 f \n';
  for (const off of offsets) {
    pdf += `${off.toString().padStart(10, '0')} 00000 n \n`;
  }
  pdf += `trailer\n<< /Size ${size} /Root 1 0 R >>\nstartxref\n${xrefStart}\n%%EOF\n`;

  return Buffer.from(pdf, 'latin1');
}
