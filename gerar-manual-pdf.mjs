/* ===========================================================================
   AgendaPro — gera o PDF do manual a partir do manual.html

     node gerar-manual-pdf.mjs

   O PDF não é escrito à mão: é a mesma página, impressa pelo Chromium com o
   CSS de impressão dela. Um texto só, dois formatos — mexeu no manual.html,
   rode isto e publique os dois juntos, senão o "Baixar em PDF" entrega o
   manual de ontem.
   =========================================================================== */
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const RAIZ = path.dirname(fileURLToPath(import.meta.url));

const nav = await chromium.launch();
const pg = await nav.newPage();
await pg.goto(pathToFileURL(path.join(RAIZ, 'manual.html')).href, { waitUntil: 'load' });
await pg.emulateMedia({ media: 'print', colorScheme: 'light' });
await pg.pdf({
  path: path.join(RAIZ, 'manual-agendapro.pdf'),
  format: 'A4',
  printBackground: true,
  margin: { top: '18mm', bottom: '18mm', left: '16mm', right: '16mm' },
  displayHeaderFooter: true,
  headerTemplate: '<span></span>',
  footerTemplate: `<div style="width:100%;font:9px system-ui,sans-serif;color:#888;
    padding:0 16mm;display:flex;justify-content:space-between">
    <span>Manual do AgendaPro</span>
    <span><span class="pageNumber"></span> / <span class="totalPages"></span></span></div>`,
});
await nav.close();
console.log('manual-agendapro.pdf pronto');
