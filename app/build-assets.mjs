import {createRequire} from 'node:module';import {mkdir,copyFile} from 'node:fs/promises';import path from 'node:path';import {fileURLToPath} from 'node:url';
const root=path.dirname(fileURLToPath(import.meta.url)),require=createRequire(import.meta.url);
const packageRoot=path.dirname(require.resolve('pdfjs-dist/package.json'));const dest=path.join(root,'public/vendor');await mkdir(dest,{recursive:true});
await Promise.all(['build/pdf.min.js','build/pdf.worker.min.js','LICENSE'].map(file=>copyFile(path.join(packageRoot,file),path.join(dest,path.basename(file)))));
console.log('Pinned PDF renderer copied into application assets.');

const rangeRoot=path.dirname(require.resolve('pdf-lib/package.json'));await copyFile(path.join(rangeRoot,'dist/pdf-lib.min.js'),path.join(dest,'pdf-lib.min.js'));await copyFile(path.join(rangeRoot,'LICENSE.md'),path.join(dest,'pdf-lib-LICENSE.md'));
